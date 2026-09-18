// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV3.sol";

contract UpgradeStablecoinV3Script is Script {
    function setUp() public {}

    address constant PROXY_ADMIN = 0x842d6bB2DCDcC5470A068515EDD7467457497B5d;
    address constant PROXY = 0x2e9AEBB9DEEbc0555694aA076FDD55AF999A9EF5;

    function run() external {
        vm.startBroadcast();

        StablecoinV3 newImpl = new StablecoinV3();
        console.log("New Implementation:", address(newImpl));

        bytes memory initData = abi.encodeWithSelector(
            StablecoinV3.initializeV3.selector
        );
        console.log("upgradeAndCall initData:");
        console.logBytes(initData);

        // Executed by the owner via the ProxyAdmin, not by this script:
        // ProxyAdmin admin = ProxyAdmin(PROXY_ADMIN);
        // TransparentUpgradeableProxy proxyInstance = TransparentUpgradeableProxy(payable(PROXY));
        // admin.upgradeAndCall(proxyInstance, address(newImpl), initData);

        // Then, once the CCIP BurnMintTokenPool is deployed for this chain:
        // StablecoinV3(PROXY).grantMintAndBurnRoles(POOL);

        vm.stopBroadcast();
    }
}
