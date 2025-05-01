// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeBeaconProxies is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconOwner = vm.envAddress("BEACON_OWNER_ADDRESS");

        // The addresses of the deployed beacons
        address balanceManagerBeacon = vm.envAddress("BEACON_BALANCEMANAGER");
        address poolManagerBeacon = vm.envAddress("BEACON_POOLMANAGER");
        address routerBeacon = vm.envAddress("BEACON_ROUTER");
        address orderBookBeacon = vm.envAddress("BEACON_ORDERBOOK");

        // The addresses of the proxy instances
        address balanceManagerProxy = vm.envAddress("PROXY_BALANCEMANAGER");
        address poolManagerProxy = vm.envAddress("PROXY_POOLMANAGER");
        address routerProxy = vm.envAddress("PROXY_ROUTER");

        vm.startBroadcast(deployerPrivateKey);

        console.log("========== UPGRADING BEACON IMPLEMENTATIONS ==========");
        // Upgrade the implementations
        Upgrades.upgradeBeacon(balanceManagerBeacon, "BalanceManagerV2.sol");
        console.log("Upgraded BalanceManager beacon to V2");

        Upgrades.upgradeBeacon(poolManagerBeacon, "PoolManagerV2.sol");
        console.log("Upgraded PoolManager beacon to V2");

        Upgrades.upgradeBeacon(routerBeacon, "GTXRouterV2.sol");
        console.log("Upgraded GTXRouter beacon to V2");

        Upgrades.upgradeBeacon(orderBookBeacon, "OrderBookV2.sol");
        console.log("Upgraded OrderBook beacon to V2");

        console.log("\n========== VERIFYING UPGRADES ==========");
        // Verify upgrades by calling the new getVersion function on each proxy
        string memory balanceVersion = _callGetVersion(balanceManagerProxy);
        string memory poolVersion = _callGetVersion(poolManagerProxy);
        string memory routerVersion = _callGetVersion(routerProxy);

        console.log("BalanceManager version: %s", balanceVersion);
        console.log("PoolManager version: %s", poolVersion);
        console.log("GTXRouter version: %s", routerVersion);

        vm.stopBroadcast();
    }

    function _callGetVersion(
        address proxy
    ) internal view returns (string memory) {
        bytes4 selector = bytes4(keccak256("getVersion()"));

        (bool success, bytes memory data) = proxy.staticcall(abi.encodeWithSelector(selector));

        if (!success) {
            return "Failed to get version";
        }

        return abi.decode(data, (string));
    }
}
