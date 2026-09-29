// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV3.sol";

contract UpgradeStablecoinV3Script is Script {
    function setUp() public {}

    // CAUTION: per-deployment values, copied from script/UpgradeStablecoin.s.sol.
    // They are correct for exactly one chain's proxy/ProxyAdmin pair and will be
    // wrong on every other chain. Since CCIP deployments are inherently
    // multi-chain, these MUST be reconfirmed against the target chain before
    // running this script with --broadcast.
    address constant PROXY_ADMIN = 0x36124fa57E049846e9dc181C8cAA31A3C5da4E9c;
    address constant PROXY = 0xcE24439F2D9C6a2289F741120FE202248B666666;

    // Initial CCIP Token Administrator seeded by initializeV3. Override per
    // deployment with `CCIP_ADMIN=0x...`; defaults to the deployer so a dry run
    // without the env var still produces valid calldata. Must not be address(0)
    // — initializeV3 reverts on it.
    address constant DEFAULT_CCIP_ADMIN = 0x36124fa57E049846e9dc181C8cAA31A3C5da4E9c;

    function run() external {
        address ccipAdmin = vm.envOr("CCIP_ADMIN", DEFAULT_CCIP_ADMIN);
        require(ccipAdmin != address(0), "CCIP_ADMIN must not be the zero address");
        console.log("Initial CCIP admin:", ccipAdmin);

        vm.startBroadcast();

        StablecoinV3 newImpl = new StablecoinV3();
        console.log("New Implementation:", address(newImpl));

        bytes memory initData = abi.encodeWithSelector(
            StablecoinV3.initializeV3.selector,
            ccipAdmin
        );
        console.log("upgradeAndCall initData:");
        console.logBytes(initData);

        // Executed by the owner via the ProxyAdmin, not by this script:
        ProxyAdmin admin = ProxyAdmin(PROXY_ADMIN);
        TransparentUpgradeableProxy proxyInstance = TransparentUpgradeableProxy(payable(PROXY));
        admin.upgradeAndCall(proxyInstance, address(newImpl), initData);

        // Then, once the CCIP BurnMintTokenPool is deployed for this chain:
        // StablecoinV3(PROXY).grantMintAndBurnRoles(POOL);

        vm.stopBroadcast();
    }
}
