// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";
import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeBeaconProxies is DeployHelpers {
    function run() public {
        loadDeployments();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Uncomment the functions you want to execute
        upgradeOrderBook();
        upgradeBalanceManager();
        upgradePoolManager();
        upgradeRouter();

        vm.stopBroadcast();
    }

    function upgradeOrderBook() internal {
        address orderBookBeacon = deployed["BEACON_ORDERBOOK"].addr;
        if (!deployed["BEACON_ORDERBOOK"].isSet) {
            revert("OrderBook beacon address not found in deployments");
        }

        Upgrades.upgradeBeacon(orderBookBeacon, "OrderBookV2.sol");
        console.log("Upgraded OrderBook beacon to V2");
    }

    function upgradeBalanceManager() internal {
        address balanceManagerBeacon = deployed["BEACON_BALANCEMANAGER"].addr;
        if (!deployed["BEACON_BALANCEMANAGER"].isSet) {
            revert("BalanceManager beacon address not found in deployments");
        }

        Upgrades.upgradeBeacon(balanceManagerBeacon, "BalanceManagerV2.sol");
        console.log("Upgraded BalanceManager beacon to V2");
    }

    function upgradePoolManager() internal {
        address poolManagerBeacon = deployed["BEACON_POOLMANAGER"].addr;
        if (!deployed["BEACON_POOLMANAGER"].isSet) {
            revert("PoolManager beacon address not found in deployments");
        }

        Upgrades.upgradeBeacon(poolManagerBeacon, "PoolManagerV2.sol");
        console.log("Upgraded PoolManager beacon to V2");
    }

    function upgradeRouter() internal {
        address routerBeacon = deployed["BEACON_ROUTER"].addr;
        if (!deployed["BEACON_ROUTER"].isSet) {
            revert("Router beacon address not found in deployments");
        }

        Upgrades.upgradeBeacon(routerBeacon, "GTXRouterV2.sol");
        console.log("Upgraded Router beacon to V2");
    }
}
