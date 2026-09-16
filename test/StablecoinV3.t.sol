// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV3.sol";

contract StablecoinV3Test is Test {
    string internal constant NAME = "United Stables";
    string internal constant SYMBOL = "U";

    // Storage slots asserted directly, per the design doc.
    uint256 internal constant SLOT_V2_GAP_START = 361;
    uint256 internal constant SLOT_V2_GAP_END = 408;
    uint256 internal constant SLOT_IS_CCIP_MINTER_BURNER = 409;
    uint256 internal constant SLOT_CCIP_ADMIN = 410;
    uint256 internal constant SLOT_GAP_V3_START = 411;

    // Nonce used solely to write a deterministic entry into `_authorizationStates`
    // (slot 359) via `cancelAuthorization`, which needs no signature.
    bytes32 internal constant INVARIANCE_NONCE = keccak256("invariance");

    StablecoinV3 internal token;
    ProxyAdmin internal proxyAdmin;
    TransparentUpgradeableProxy internal proxy;

    uint256 internal ownerPrivateKey;
    address internal owner;
    address internal autoOwner;
    address internal alice;
    address internal bob;
    address internal pool;

    /// @dev Deploys the proxy on Stablecoin, upgrades it to V2, and populates
    ///      most V1/V2 storage-backed values (balances, frozen, nonce, chainId,
    ///      autoOwner, autoMintMaxLimit) so the V3 upgrade has something
    ///      meaningful to preserve. `test_UpgradeToV3_PreservesAllExistingState`
    ///      populates the remaining storage-backed values (an allowance,
    ///      `_authorizationStates`, and `_paused`) itself, immediately before
    ///      taking its snapshot, because pausing here would block every other
    ///      test in this file that shares this fixture.
    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        autoOwner = vm.addr(0xC0C);
        alice = vm.addr(0xA11);
        bob = vm.addr(0xB0B);
        pool = address(0xCC1B);

        vm.startPrank(owner);

        Stablecoin impl = new Stablecoin();
        proxyAdmin = new ProxyAdmin();
        proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            abi.encodeWithSignature("initialize(string,string)", NAME, SYMBOL)
        );

        StablecoinV2 v2Impl = new StablecoinV2();
        proxyAdmin.upgradeAndCall(
            proxy,
            address(v2Impl),
            abi.encodeWithSelector(StablecoinV2.initializeV2.selector)
        );

        token = StablecoinV3(address(proxy));

        token.transferAutoOwnership(autoOwner);
        token.setAutoMintMaxLimit(500e18);
        token.mint(1_000e18);
        token.mint(alice, 250e18);
        token.freeze(bob);

        vm.stopPrank();

        // Advance `nonce` through the auto path so it is non-zero before the upgrade.
        vm.prank(autoOwner);
        token.autoMint(alice, 10e18, 0, block.chainid);
    }

    function _upgradeToV3() internal {
        vm.startPrank(owner);
        StablecoinV3 v3Impl = new StablecoinV3();
        proxyAdmin.upgradeAndCall(
            proxy,
            address(v3Impl),
            abi.encodeWithSelector(StablecoinV3.initializeV3.selector)
        );
        vm.stopPrank();
    }

    /// @dev Bundles the pre-upgrade snapshot into a single memory struct so the
    ///      test function only needs one local slot across the upgrade call —
    ///      the flat-locals version of this snapshot overflows the EVM stack
    ///      (`Stack too deep`) under the legacy (non-via-IR) codegen this
    ///      project builds with. Same values, same assertions, just packed.
    struct Snapshot {
        string name;
        string symbol;
        uint8 decimals;
        uint256 totalSupply;
        uint256 ownerBalance;
        uint256 aliceBalance;
        bool bobFrozen;
        uint256 nonce;
        uint256 chainId;
        address autoOwner;
        uint256 autoMintMaxLimit;
        bool eip7598Enabled;
        address owner;
        bool paused;
        bytes32 domainSeparator;
        uint256 allowanceAliceFromOwner;
        bool authorizationUsed;
    }

    function _snapshot() internal view returns (Snapshot memory s) {
        s.name = token.name();
        s.symbol = token.symbol();
        s.decimals = token.decimals();
        s.totalSupply = token.totalSupply();
        s.ownerBalance = token.balanceOf(owner);
        s.aliceBalance = token.balanceOf(alice);
        s.bobFrozen = token.frozen(bob);
        s.nonce = token.nonce();
        s.chainId = token.chainId();
        s.autoOwner = token.autoOwner();
        s.autoMintMaxLimit = token.autoMintMaxLimit();
        s.eip7598Enabled = token.eip7598EnableFlag();
        s.owner = token.owner();
        s.paused = token.paused();
        s.domainSeparator = token.DOMAIN_SEPARATOR();
        s.allowanceAliceFromOwner = token.allowance(owner, alice);
        s.authorizationUsed = token.authorizationState(owner, INVARIANCE_NONCE);
    }

    function test_UpgradeToV3_PreservesAllExistingState() public {
        // Populate the storage-backed values the base fixture leaves untouched, so
        // this test can actually detect corruption of them. Confined to this test
        // body (not setUp()) so no other test in this file is affected — Foundry
        // re-runs setUp() fresh per test.
        vm.startPrank(owner);
        token.approve(alice, 123e18);                        // allowance
        token.cancelAuthorization(owner, INVARIANCE_NONCE);   // _authorizationStates slot 359
        token.pause();                                        // _paused slot 304
        vm.stopPrank();

        // Snapshot every V1/V2 storage-backed value before the upgrade.
        Snapshot memory before = _snapshot();

        _upgradeToV3();

        assertEq(token.name(), before.name, "name");
        assertEq(token.symbol(), before.symbol, "symbol");
        // decimals() on ERC20Upgradeable returns the literal 18 and reads no
        // storage slot, so this assertion documents intent rather than
        // detecting corruption.
        assertEq(token.decimals(), before.decimals, "decimals");
        assertEq(token.totalSupply(), before.totalSupply, "totalSupply");
        assertEq(token.balanceOf(owner), before.ownerBalance, "owner balance");
        assertEq(token.balanceOf(alice), before.aliceBalance, "alice balance");
        assertEq(token.frozen(bob), before.bobFrozen, "frozen");
        assertEq(token.nonce(), before.nonce, "nonce");
        assertEq(token.chainId(), before.chainId, "chainId");
        assertEq(token.autoOwner(), before.autoOwner, "autoOwner");
        assertEq(token.autoMintMaxLimit(), before.autoMintMaxLimit, "autoMintMaxLimit");
        assertEq(token.eip7598EnableFlag(), before.eip7598Enabled, "eip7598EnableFlag");
        assertEq(token.owner(), before.owner, "owner");
        assertEq(token.paused(), before.paused, "paused");
        assertEq(token.DOMAIN_SEPARATOR(), before.domainSeparator, "DOMAIN_SEPARATOR");
        assertEq(token.allowance(owner, alice), before.allowanceAliceFromOwner, "allowance");
        assertEq(
            token.authorizationState(owner, INVARIANCE_NONCE),
            before.authorizationUsed,
            "authorizationState"
        );

        // Sanity: the snapshot was not trivially empty.
        assertGt(before.totalSupply, 0, "fixture minted nothing");
        assertGt(before.nonce, 0, "fixture left nonce at zero");
        assertTrue(before.bobFrozen, "fixture froze nobody");
        assertGt(before.allowanceAliceFromOwner, 0, "fixture set no allowance");
        assertTrue(before.authorizationUsed, "fixture consumed no authorization");
        assertTrue(before.paused, "fixture did not pause");
    }

    function test_V3StorageOccupiesSlot409AndAbove() public {
        _upgradeToV3();

        // V2's gap must still be entirely zero.
        for (uint256 slot = SLOT_V2_GAP_START; slot <= SLOT_V2_GAP_END; slot++) {
            assertEq(
                vm.load(address(proxy), bytes32(slot)),
                bytes32(0),
                "V2 __gap slot was written"
            );
        }

        // initializeV3 sets _ccipAdmin at slot 410.
        assertEq(
            vm.load(address(proxy), bytes32(SLOT_CCIP_ADMIN)),
            bytes32(uint256(uint160(owner))),
            "_ccipAdmin is not at slot 410"
        );

        // Slot 409 is a mapping root: it must stay empty, and nothing may sit
        // past the V3 block either. Task 3 asserts a granted entry actually
        // hashes into this root, which is the substantive half of the check.
        assertEq(
            vm.load(address(proxy), bytes32(SLOT_IS_CCIP_MINTER_BURNER)),
            bytes32(0),
            "mapping root slot 409 is not empty"
        );
        assertEq(
            vm.load(address(proxy), bytes32(SLOT_GAP_V3_START)),
            bytes32(0),
            "__gapV3 does not start at slot 411"
        );
    }

    function test_InitializeV3_CannotBeCalledTwice() public {
        _upgradeToV3();
        vm.expectRevert("Initializable: contract is already initialized");
        token.initializeV3();
    }

    function test_GrantMintAndBurnRoles_SetsFlagAndEmits() public {
        _upgradeToV3();

        assertFalse(token.isCCIPMinterBurner(pool));

        vm.expectEmit(true, false, false, false, address(token));
        emit StablecoinV3.CCIPRolesGranted(pool);

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        assertTrue(token.isCCIPMinterBurner(pool));
    }

    function test_RevokeMintAndBurnRoles_ClearsFlagAndEmits() public {
        _upgradeToV3();

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        vm.expectEmit(true, false, false, false, address(token));
        emit StablecoinV3.CCIPRolesRevoked(pool);

        vm.prank(owner);
        token.revokeMintAndBurnRoles(pool);

        assertFalse(token.isCCIPMinterBurner(pool));
    }

    function test_GrantMintAndBurnRoles_RevertsForNonOwner() public {
        _upgradeToV3();

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        token.grantMintAndBurnRoles(pool);
    }

    function test_RevokeMintAndBurnRoles_RevertsForNonOwner() public {
        _upgradeToV3();

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(alice);
        token.revokeMintAndBurnRoles(pool);
    }

    function test_GrantMintAndBurnRoles_RevertsOnZeroAddress() public {
        _upgradeToV3();

        vm.expectRevert(
            abi.encodeWithSelector(Stablecoin.NotAllowedAddress.selector, address(0))
        );
        vm.prank(owner);
        token.grantMintAndBurnRoles(address(0));
    }

    /// @dev Completes the slot-409 assertion begun in
    ///      test_V3StorageOccupiesSlot409AndAbove: a granted entry must hash to
    ///      the mapping rooted at 409, and nothing in V2's gap may move.
    function test_GrantMintAndBurnRoles_WritesMappingRootedAtSlot409() public {
        _upgradeToV3();

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        bytes32 entry = keccak256(abi.encode(pool, SLOT_IS_CCIP_MINTER_BURNER));
        assertEq(
            vm.load(address(proxy), entry),
            bytes32(uint256(1)),
            "isCCIPMinterBurner is not rooted at slot 409"
        );

        for (uint256 slot = SLOT_V2_GAP_START; slot <= SLOT_V2_GAP_END; slot++) {
            assertEq(
                vm.load(address(proxy), bytes32(slot)),
                bytes32(0),
                "granting a role wrote into V2's __gap"
            );
        }
    }

    function test_Mint_AllowedForGrantedPool() public {
        _upgradeToV3();

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(pool);
        bool ok = token.mint(alice, 100e18);

        assertTrue(ok);
        assertEq(token.totalSupply(), supplyBefore + 100e18);
        assertEq(token.balanceOf(alice), 260e18 + 100e18);
    }

    function test_Mint_StillAllowedForOwner() public {
        _upgradeToV3();

        uint256 supplyBefore = token.totalSupply();

        vm.prank(owner);
        token.mint(alice, 5e18);

        assertEq(token.totalSupply(), supplyBefore + 5e18);
    }

    function test_Mint_RevertsForRevokedPool() public {
        _upgradeToV3();

        vm.startPrank(owner);
        token.grantMintAndBurnRoles(pool);
        token.revokeMintAndBurnRoles(pool);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(StablecoinV3.CallerNotOwnerOrCCIP.selector, pool)
        );
        vm.prank(pool);
        token.mint(alice, 1e18);
    }

    function test_Mint_RevertsForArbitraryCaller() public {
        _upgradeToV3();

        vm.expectRevert(
            abi.encodeWithSelector(StablecoinV3.CallerNotOwnerOrCCIP.selector, alice)
        );
        vm.prank(alice);
        token.mint(alice, 1e18);
    }

    /// @dev Spec §6: CCIP mint is NOT exempt from the freeze check. A frozen
    ///      recipient makes the destination-chain mint revert, which strands the
    ///      CCIP message. That is the accepted trade-off; pre-flight checks in
    ///      the submitting service are the mitigation.
    function test_Mint_RevertsWhenRecipientFrozen() public {
        _upgradeToV3();

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        vm.expectRevert(
            abi.encodeWithSelector(Stablecoin.FrozenAddress.selector, bob)
        );
        vm.prank(pool);
        token.mint(bob, 1e18);
    }

    /// @dev Spec §6: CCIP mint is NOT exempt from pause either.
    function test_Mint_RevertsWhenPaused() public {
        _upgradeToV3();

        vm.startPrank(owner);
        token.grantMintAndBurnRoles(pool);
        token.pause();
        vm.stopPrank();

        vm.expectRevert("Pausable: paused");
        vm.prank(pool);
        token.mint(alice, 1e18);
    }

    /// @dev Spec §7: the CCIP path is bounded only by the pool's CCIP rate
    ///      limiter, not by autoMintMaxLimit. Accepted and recorded.
    function test_Mint_ByPoolIsNotBoundedByAutoMintMaxLimit() public {
        _upgradeToV3();

        vm.prank(owner);
        token.grantMintAndBurnRoles(pool);

        uint256 limit = token.autoMintMaxLimit();
        assertGt(limit, 0, "fixture left autoMintMaxLimit at zero");

        vm.prank(pool);
        token.mint(alice, limit * 10);

        assertEq(token.balanceOf(alice), 260e18 + limit * 10);
    }

    function test_Burn_BurnsFromCallerBalanceForGrantedPool() public {
        _upgradeToV3();

        vm.startPrank(owner);
        token.grantMintAndBurnRoles(pool);
        token.transfer(pool, 40e18);
        vm.stopPrank();

        uint256 supplyBefore = token.totalSupply();

        vm.prank(pool);
        bool ok = token.burn(40e18);

        assertTrue(ok);
        assertEq(token.balanceOf(pool), 0, "pool balance not burned");
        assertEq(token.totalSupply(), supplyBefore - 40e18, "totalSupply");
    }

    function test_Burn_StillAllowedForOwner() public {
        _upgradeToV3();

        uint256 supplyBefore = token.totalSupply();

        vm.prank(owner);
        token.burn(10e18);

        assertEq(token.totalSupply(), supplyBefore - 10e18);
    }

    function test_Burn_RevertsForArbitraryCaller() public {
        _upgradeToV3();

        vm.expectRevert(
            abi.encodeWithSelector(StablecoinV3.CallerNotOwnerOrCCIP.selector, alice)
        );
        vm.prank(alice);
        token.burn(1e18);
    }

    function test_Burn_RevertsForRevokedPool() public {
        _upgradeToV3();

        vm.startPrank(owner);
        token.grantMintAndBurnRoles(pool);
        token.transfer(pool, 5e18);
        token.revokeMintAndBurnRoles(pool);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(StablecoinV3.CallerNotOwnerOrCCIP.selector, pool)
        );
        vm.prank(pool);
        token.burn(5e18);
    }

    /// @dev Spec §5.1: burn deliberately does NOT gain whenNotPaused, matching V1.
    ///      Pause is already enforced on the outbound path, because the Router's
    ///      transfer of tokens into the pool goes through the paused _transfer.
    function test_Burn_IsNotBlockedByPause() public {
        _upgradeToV3();

        vm.startPrank(owner);
        token.grantMintAndBurnRoles(pool);
        token.transfer(pool, 7e18);
        token.pause();
        vm.stopPrank();

        vm.prank(pool);
        token.burn(7e18);

        assertEq(token.balanceOf(pool), 0);
    }

    /// @dev The freeze check on _transfer is what actually stops a frozen holder
    ///      from bridging out, before any burn happens.
    function test_FrozenHolderCannotTransferIntoPool() public {
        _upgradeToV3();

        vm.startPrank(owner);
        token.grantMintAndBurnRoles(pool);
        token.transfer(alice, 20e18);
        token.freeze(alice);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(Stablecoin.FrozenAddress.selector, alice)
        );
        vm.prank(alice);
        token.transfer(pool, 20e18);
    }
}
