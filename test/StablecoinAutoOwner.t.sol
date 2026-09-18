// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Stablecoin.sol";
import {StablecoinAutoOwner, IStablecoinAutoMintBurn} from "../src/StablecoinAutoOwner.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StablecoinAutoOwnerV2Mock is StablecoinAutoOwner {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract StablecoinAutoOwnerTest is Test {
    Stablecoin internal token;
    StablecoinAutoOwner internal autoCtl;
    StablecoinAutoOwner internal autoImpl;

    address internal tokenOwner = address(0xA11CE);
    address internal ctlOwner = address(0xAD31);
    address internal operator = address(0x09ED);
    address internal stranger = address(0x5151);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);
    address internal charlie = address(0xC0FFEE);

    uint256 internal constant GLOBAL_CAP = 1_000_000 ether;

    event StablecoinSet(address indexed stablecoin);
    event WhitelistUpdated(address indexed to, bool flag);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        // Deploy Stablecoin behind a transparent proxy (existing project convention).
        vm.startPrank(tokenOwner);
        Stablecoin impl = new Stablecoin();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(string,string)", "United Stables", "U")
        );
        token = Stablecoin(address(proxy));

        // Owner needs balance for autoBurn. Also sets a global autoMintMaxLimit.
        token.setAutoMintMaxLimit(GLOBAL_CAP);
        token.mint(10_000 ether); // minted to tokenOwner

        // Deploy StablecoinAutoOwner behind an ERC1967 proxy (UUPS).
        autoImpl = new StablecoinAutoOwner();
        ERC1967Proxy autoProxy = new ERC1967Proxy(
            address(autoImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(token),
                ctlOwner,
                operator
            )
        );
        autoCtl = StablecoinAutoOwner(address(autoProxy));

        // Install the controller as autoOwner on Stablecoin.
        token.transferAutoOwnership(address(autoCtl));
        vm.stopPrank();

        // Seed the whitelist with alice and bob.
        vm.startPrank(ctlOwner);
        autoCtl.setWhitelist(alice, true);
        autoCtl.setWhitelist(bob, true);
        vm.stopPrank();
    }

    // -------- Initialization --------

    function test_Init_State() public {
        assertEq(address(autoCtl.stablecoin()), address(token));
        assertEq(autoCtl.owner(), ctlOwner);
        assertEq(autoCtl.operator(), operator);
        assertFalse(autoCtl.paused());
    }

    function test_Init_RevertZeroStablecoin() public {
        StablecoinAutoOwner fresh = new StablecoinAutoOwner();
        vm.expectRevert(StablecoinAutoOwner.ZeroAddress.selector);
        new ERC1967Proxy(
            address(fresh),
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(0),
                ctlOwner,
                operator
            )
        );
    }

    function test_Init_RevertZeroOwner() public {
        StablecoinAutoOwner fresh = new StablecoinAutoOwner();
        vm.expectRevert(StablecoinAutoOwner.ZeroAddress.selector);
        new ERC1967Proxy(
            address(fresh),
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(token),
                address(0),
                operator
            )
        );
    }

    function test_Init_RevertZeroOperator() public {
        StablecoinAutoOwner fresh = new StablecoinAutoOwner();
        vm.expectRevert(StablecoinAutoOwner.ZeroAddress.selector);
        new ERC1967Proxy(
            address(fresh),
            abi.encodeWithSignature(
                "initialize(address,address,address)",
                address(token),
                ctlOwner,
                address(0)
            )
        );
    }

    function test_Init_CannotReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        autoCtl.initialize(address(token), ctlOwner, operator);
    }

    function test_Init_ImplementationDisabled() public {
        vm.expectRevert("Initializable: contract is already initialized");
        autoImpl.initialize(address(token), ctlOwner, operator);
    }

    // -------- autoMint --------

    function test_AutoMint_Success() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        bool ok = autoCtl.autoMint(alice, 100 ether, seq, block.chainid);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.nonce(), seq + 1);
    }

    function test_AutoMint_Success_AtGlobalCap() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        bool ok = autoCtl.autoMint(alice, GLOBAL_CAP, seq, block.chainid);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), GLOBAL_CAP);
    }

    function test_AutoMint_RevertZeroTo() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(StablecoinAutoOwner.ZeroAddress.selector);
        autoCtl.autoMint(address(0), 1, seq, block.chainid);
    }

    function test_AutoMint_RevertZeroAmount() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(StablecoinAutoOwner.ZeroAmount.selector);
        autoCtl.autoMint(alice, 0, seq, block.chainid);
    }

    function test_AutoMint_RevertNotWhitelisted() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(StablecoinAutoOwner.NotWhitelisted.selector, charlie));
        autoCtl.autoMint(charlie, 1, seq, block.chainid);
    }

    function test_AutoMint_RevertAboveGlobalCap() public {
        // Stablecoin.autoMint enforces the global cap.
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert();
        autoCtl.autoMint(alice, GLOBAL_CAP + 1, seq, block.chainid);
    }

    function test_AutoMint_RevertNonOperator() public {
        uint256 seq = token.nonce();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(StablecoinAutoOwner.CallerNotOperator.selector, stranger)
        );
        autoCtl.autoMint(alice, 1, seq, block.chainid);
    }

    function test_AutoMint_RevertWhenOwnerCalls() public {
        uint256 seq = token.nonce();
        vm.prank(ctlOwner);
        vm.expectRevert(
            abi.encodeWithSelector(StablecoinAutoOwner.CallerNotOperator.selector, ctlOwner)
        );
        autoCtl.autoMint(alice, 1, seq, block.chainid);
    }

    function test_AutoMint_RevertWhenPaused() public {
        vm.prank(ctlOwner);
        autoCtl.pause();
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert("Pausable: paused");
        autoCtl.autoMint(alice, 1, seq, block.chainid);
    }

    function test_AutoMint_PropagatesStablecoinInvalidNonce() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Stablecoin.InvalidNonce.selector, 999));
        autoCtl.autoMint(alice, 1, 999, block.chainid);
    }

    function test_AutoMint_PropagatesStablecoinInvalidChainId() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Stablecoin.InvalidChainId.selector, 999));
        autoCtl.autoMint(alice, 1, seq, 999);
    }

    function test_AutoMint_PropagatesStablecoinFrozen() public {
        vm.prank(tokenOwner);
        token.freeze(alice);
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Stablecoin.FrozenAddress.selector, alice));
        autoCtl.autoMint(alice, 1, seq, block.chainid);
    }

    function test_AutoMint_PropagatesStablecoinPaused() public {
        vm.prank(tokenOwner);
        token.pause();
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert("Pausable: paused");
        autoCtl.autoMint(alice, 1, seq, block.chainid);
    }

    // -------- autoBurn --------

    function test_AutoBurn_Success() public {
        uint256 burnAmt = 100 ether;
        uint256 ownerBal = token.balanceOf(tokenOwner);
        uint256 seq = token.nonce();

        vm.prank(operator);
        bool ok = autoCtl.autoBurn(burnAmt, seq, block.chainid);

        assertTrue(ok);
        assertEq(token.balanceOf(tokenOwner), ownerBal - burnAmt);
        assertEq(token.nonce(), seq + 1);
    }

    function test_AutoBurn_RevertZeroAmount() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(StablecoinAutoOwner.ZeroAmount.selector);
        autoCtl.autoBurn(0, seq, block.chainid);
    }

    function test_AutoBurn_RevertAboveGlobalCap() public {
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                StablecoinAutoOwner.AmountExceedsMaxLimit.selector,
                GLOBAL_CAP + 1,
                GLOBAL_CAP
            )
        );
        autoCtl.autoBurn(GLOBAL_CAP + 1, seq, block.chainid);
    }

    function test_AutoBurn_RevertNonOperator() public {
        uint256 seq = token.nonce();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(StablecoinAutoOwner.CallerNotOperator.selector, stranger)
        );
        autoCtl.autoBurn(1, seq, block.chainid);
    }

    function test_AutoBurn_RevertWhenOwnerCalls() public {
        uint256 seq = token.nonce();
        vm.prank(ctlOwner);
        vm.expectRevert(
            abi.encodeWithSelector(StablecoinAutoOwner.CallerNotOperator.selector, ctlOwner)
        );
        autoCtl.autoBurn(1, seq, block.chainid);
    }

    function test_AutoBurn_RevertWhenPaused() public {
        vm.prank(ctlOwner);
        autoCtl.pause();
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert("Pausable: paused");
        autoCtl.autoBurn(1, seq, block.chainid);
    }

    function test_AutoBurn_PropagatesStablecoinInvalidNonce() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(Stablecoin.InvalidNonce.selector, 42));
        autoCtl.autoBurn(1, 42, block.chainid);
    }

    // -------- setWhitelist --------

    function test_SetWhitelist_Add_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(autoCtl));
        emit WhitelistUpdated(charlie, true);

        vm.prank(ctlOwner);
        autoCtl.setWhitelist(charlie, true);

        assertTrue(autoCtl.isWhitelisted(charlie));
    }

    function test_SetWhitelist_Remove_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(autoCtl));
        emit WhitelistUpdated(alice, false);

        vm.prank(ctlOwner);
        autoCtl.setWhitelist(alice, false);

        assertFalse(autoCtl.isWhitelisted(alice));
    }

    function test_SetWhitelist_RemoveBlocksMint() public {
        vm.prank(ctlOwner);
        autoCtl.setWhitelist(alice, false);

        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(StablecoinAutoOwner.NotWhitelisted.selector, alice));
        autoCtl.autoMint(alice, 1, seq, block.chainid);
    }

    function test_SetWhitelist_AddIdempotent_NoEvent() public {
        // alice already whitelisted — re-adding should not emit.
        vm.recordLogs();
        vm.prank(ctlOwner);
        autoCtl.setWhitelist(alice, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    function test_SetWhitelist_RemoveIdempotent_NoEvent() public {
        // charlie was never whitelisted — removing should not emit.
        vm.recordLogs();
        vm.prank(ctlOwner);
        autoCtl.setWhitelist(charlie, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0);
    }

    function test_SetWhitelist_RevertZeroAddress() public {
        vm.prank(ctlOwner);
        vm.expectRevert(StablecoinAutoOwner.ZeroAddress.selector);
        autoCtl.setWhitelist(address(0), true);
    }

    function test_SetWhitelist_RevertNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.setWhitelist(charlie, true);
    }

    function test_SetWhitelistBatch_Success() public {
        address[] memory addrs = new address[](2);
        bool[] memory flags = new bool[](2);
        addrs[0] = charlie;
        flags[0] = true;
        addrs[1] = alice;
        flags[1] = false;

        vm.prank(ctlOwner);
        autoCtl.setWhitelistBatch(addrs, flags);

        assertTrue(autoCtl.isWhitelisted(charlie));
        assertFalse(autoCtl.isWhitelisted(alice));
        assertTrue(autoCtl.isWhitelisted(bob));
    }

    function test_SetWhitelistBatch_RevertLengthMismatch() public {
        address[] memory addrs = new address[](2);
        bool[] memory flags = new bool[](1);
        addrs[0] = charlie;
        addrs[1] = alice;
        flags[0] = true;

        vm.prank(ctlOwner);
        vm.expectRevert(StablecoinAutoOwner.LengthMismatch.selector);
        autoCtl.setWhitelistBatch(addrs, flags);
    }

    function test_SetWhitelistBatch_RevertNonOwner() public {
        address[] memory addrs = new address[](0);
        bool[] memory flags = new bool[](0);
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.setWhitelistBatch(addrs, flags);
    }

    // -------- whitelist views --------

    function test_Whitelist_Views() public {
        assertTrue(autoCtl.isWhitelisted(alice));
        assertTrue(autoCtl.isWhitelisted(bob));
        assertFalse(autoCtl.isWhitelisted(charlie));

        assertEq(autoCtl.whitelistLength(), 2);

        address[] memory all = autoCtl.getWhitelist();
        assertEq(all.length, 2);
        // Order of EnumerableSet is insertion order until removals occur.
        assertEq(all[0], alice);
        assertEq(all[1], bob);

        assertEq(autoCtl.whitelistAt(0), alice);
        assertEq(autoCtl.whitelistAt(1), bob);
    }

    function test_Whitelist_ViewsAfterRemoval() public {
        vm.prank(ctlOwner);
        autoCtl.setWhitelist(alice, false);

        assertFalse(autoCtl.isWhitelisted(alice));
        assertTrue(autoCtl.isWhitelisted(bob));
        assertEq(autoCtl.whitelistLength(), 1);

        address[] memory all = autoCtl.getWhitelist();
        assertEq(all.length, 1);
        assertEq(all[0], bob);
    }

    function test_Whitelist_WhitelistAtRevertsOutOfBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(StablecoinAutoOwner.IndexOutOfBounds.selector, 2, 2)
        );
        autoCtl.whitelistAt(2);
    }

    // -------- pause/unpause --------

    function test_Pause_OwnerOnly() public {
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.pause();

        vm.prank(ctlOwner);
        autoCtl.pause();
        assertTrue(autoCtl.paused());
    }

    function test_Unpause_Works() public {
        vm.prank(ctlOwner);
        autoCtl.pause();

        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.unpause();

        vm.prank(ctlOwner);
        autoCtl.unpause();
        assertFalse(autoCtl.paused());
    }

    // -------- views --------

    function test_Views_ReflectStablecoin() public {
        assertEq(autoCtl.nonce(), token.nonce());
        assertEq(autoCtl.chainId(), token.chainId());

        // After a mint, nonce advances and the view reflects it.
        uint256 seq = token.nonce();
        vm.prank(operator);
        autoCtl.autoMint(alice, 1, seq, block.chainid);
        assertEq(autoCtl.nonce(), seq + 1);
    }

    // -------- ownership (two-step) --------

    function test_Ownership_TwoStepTransfer() public {
        vm.prank(ctlOwner);
        autoCtl.transferOwnership(stranger);
        assertEq(autoCtl.owner(), ctlOwner);
        assertEq(autoCtl.pendingOwner(), stranger);

        // Old owner still has privileges.
        vm.prank(ctlOwner);
        autoCtl.pause();

        // Pending owner cannot yet use owner-only functions.
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.unpause();

        vm.prank(stranger);
        autoCtl.acceptOwnership();
        assertEq(autoCtl.owner(), stranger);
    }

    // -------- UUPS upgrade --------

    function test_Upgrade_OwnerCanUpgrade() public {
        StablecoinAutoOwnerV2Mock v2 = new StablecoinAutoOwnerV2Mock();
        vm.prank(ctlOwner);
        autoCtl.upgradeTo(address(v2));

        // State preserved.
        assertEq(address(autoCtl.stablecoin()), address(token));
        assertTrue(autoCtl.isWhitelisted(alice));
        assertTrue(autoCtl.isWhitelisted(bob));

        // New method callable.
        assertEq(StablecoinAutoOwnerV2Mock(address(autoCtl)).version(), "v2");
    }

    function test_Upgrade_RevertNonOwner() public {
        StablecoinAutoOwnerV2Mock v2 = new StablecoinAutoOwnerV2Mock();
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.upgradeTo(address(v2));
    }

    // -------- setOperator --------

    function test_SetOperator_Success() public {
        address newOp = address(0xDEED);
        vm.prank(ctlOwner);
        autoCtl.setOperator(newOp);
        assertEq(autoCtl.operator(), newOp);
    }

    function test_SetOperator_EmitsEvent() public {
        address newOp = address(0xDEED);
        vm.expectEmit(true, true, false, false, address(autoCtl));
        emit OperatorTransferred(operator, newOp);
        vm.prank(ctlOwner);
        autoCtl.setOperator(newOp);
    }

    function test_SetOperator_RevertZeroAddress() public {
        vm.prank(ctlOwner);
        vm.expectRevert(StablecoinAutoOwner.ZeroAddress.selector);
        autoCtl.setOperator(address(0));
    }

    function test_SetOperator_RevertNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.setOperator(address(0xDEED));

        // Operator itself cannot elevate by rotating the slot.
        vm.prank(operator);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.setOperator(address(0xDEED));
    }

    function test_SetOperator_RotationSwapsPrivileges() public {
        address newOp = address(0xDEED);
        vm.prank(ctlOwner);
        autoCtl.setOperator(newOp);

        // Old operator must no longer be able to mint.
        uint256 seq = token.nonce();
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(StablecoinAutoOwner.CallerNotOperator.selector, operator)
        );
        autoCtl.autoMint(alice, 1, seq, block.chainid);

        // New operator mints successfully.
        vm.prank(newOp);
        bool ok = autoCtl.autoMint(alice, 1, seq, block.chainid);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), 1);
    }

    // -------- operator role boundary (cannot escalate) --------

    function test_Operator_CannotSetWhitelist() public {
        vm.prank(operator);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.setWhitelist(charlie, true);
    }

    function test_Operator_CannotPause() public {
        vm.prank(operator);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.pause();
    }

    function test_Operator_CannotUpgrade() public {
        StablecoinAutoOwnerV2Mock v2 = new StablecoinAutoOwnerV2Mock();
        vm.prank(operator);
        vm.expectRevert("Ownable: caller is not the owner");
        autoCtl.upgradeTo(address(v2));
    }
}
