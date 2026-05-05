// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/StablecoinAutoOwner.sol";

/**
 * Deploys StablecoinAutoOwner behind an ERC1967 proxy (UUPS).
 *
 * Required env vars:
 *   STABLECOIN    = address of the deployed Stablecoin/StablecoinV2 proxy
 *   INITIAL_OWNER = address that will own the new controller (ideally a multisig).
 *                   Governs setMaxMintLimit / pause / upgrade / setOperator.
 *   OPERATOR      = hot-key address allowed to call autoMint / autoBurn. Should
 *                   be DIFFERENT from INITIAL_OWNER (role separation).
 *
 * Optional:
 *   TRANSFER_AUTO_OWNERSHIP = "true" to also call
 *     Stablecoin.transferAutoOwnership(proxy) from the broadcasting key. The key
 *     must be the current Stablecoin owner for this to succeed. Defaults to false
 *     so the hand-off can be done separately (e.g. from a multisig).
 *
 * Usage:
 *   forge script script/DeployStablecoinAutoOwner.s.sol \
 *     --rpc-url <RPC> --broadcast --verify \
 *     --sig "run()" \
 *     --env-file .env
 */
contract DeployStablecoinAutoOwnerScript is Script {
    function setUp() public {}

    function run() external {
        address stablecoin = vm.envAddress("STABLECOIN");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address operator = vm.envAddress("OPERATOR");
        bool transferAuto = vm.envOr("TRANSFER_AUTO_OWNERSHIP", false);

        require(stablecoin != address(0), "STABLECOIN is zero");
        require(initialOwner != address(0), "INITIAL_OWNER is zero");
        require(operator != address(0), "OPERATOR is zero");
        require(operator != initialOwner, "OPERATOR must differ from INITIAL_OWNER");

        vm.startBroadcast();

        StablecoinAutoOwner impl = new StablecoinAutoOwner();
        console.log("Implementation:", address(impl));

        bytes memory initData = abi.encodeWithSelector(
            StablecoinAutoOwner.initialize.selector,
            stablecoin,
            initialOwner,
            operator
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        console.log("Proxy:        ", address(proxy));
        console.log("Stablecoin:   ", stablecoin);
        console.log("InitialOwner: ", initialOwner);
        console.log("Operator:     ", operator);

        if (transferAuto) {
            // Broadcaster must be the current Stablecoin owner.
            (bool ok,) = stablecoin.call(
                abi.encodeWithSignature("transferAutoOwnership(address)", address(proxy))
            );
            require(ok, "transferAutoOwnership failed");
            console.log("Installed as autoOwner via transferAutoOwnership");
        } else {
            console.log(
                "NOTE: run Stablecoin.transferAutoOwnership(proxy) separately to install."
            );
        }

        vm.stopBroadcast();
    }
}
