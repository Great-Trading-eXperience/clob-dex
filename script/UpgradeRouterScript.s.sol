// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeRouterScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address routerBeacon = vm.envAddress("ROUTER_BEACON_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Upgrade the beacon to point to the new implementation
        Upgrades.upgradeBeacon(routerBeacon, "GTXRouterV2.sol");

        console.log("Router beacon upgraded to GTXRouterV2 implementation");

        vm.stopBroadcast();
    }
}
