// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/StablecoinV2.sol";

contract UpgradeStablecoinScript is Script {
    string internal constant NAME = "United Stables";
    string internal constant SYMBOL = "U";

    function setUp() public {}

    address constant PROXY_ADMIN = 0x842d6bB2DCDcC5470A068515EDD7467457497B5d;
    address constant PROXY = 0x2e9AEBB9DEEbc0555694aA076FDD55AF999A9EF5;

    function run() external {
        vm.startBroadcast();

        StablecoinV2 newImpl = new StablecoinV2();
        console.log("New Implementation:", address(newImpl));

        bytes memory initData = abi.encodeWithSelector(
            StablecoinV2.initializeV2.selector
        );
        console.logBytes(initData);

        // ProxyAdmin admin = ProxyAdmin(PROXY_ADMIN);
        // TransparentUpgradeableProxy proxyInstance = TransparentUpgradeableProxy(payable(PROXY));
        // admin.upgradeAndCall(proxyInstance, address(newImpl), initData);

        vm.stopBroadcast();
    }
}
