// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";

import "../src/OrderBook.sol";
import "../src/PoolManager.sol";

import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {PoolKey} from "../src/libraries/Pool.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "forge-std/Script.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployBeaconProxies is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconOwner = vm.envAddress("BEACON_OWNER_ADDRESS");
        address feeReceiver = vm.envAddress("FEE_RECEIVER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy beacons
        console.log("========== DEPLOYING BEACONS ==========");
        address balanceManagerBeacon = Upgrades.deployBeacon("BalanceManager.sol", beaconOwner);
        address poolManagerBeacon = Upgrades.deployBeacon("PoolManager.sol", beaconOwner);
        address routerBeacon = Upgrades.deployBeacon("GTXRouter.sol", beaconOwner);
        address orderBookBeacon = Upgrades.deployBeacon("OrderBook.sol", beaconOwner);

        console.log("BEACON_BALANCEMANAGER=%s", balanceManagerBeacon);
        console.log("BEACON_POOLMANAGER=%s", poolManagerBeacon);
        console.log("BEACON_ROUTER=%s", routerBeacon);
        console.log("BEACON_ORDERBOOK=%s", orderBookBeacon);

        // Deploy proxies for each contract
        console.log("\n========== DEPLOYING PROXIES ==========");
        address balanceManagerProxy = Upgrades.deployBeaconProxy(
            balanceManagerBeacon,
            abi.encodeCall(
                BalanceManager.initialize,
                (beaconOwner, feeReceiver, 1, 5) // owner, feeReceiver, feeMaker (0.1%), feeTaker (0.5%)
            )
        );
        console.log("PROXY_BALANCEMANAGER=%s", balanceManagerProxy);

        address poolManagerProxy = Upgrades.deployBeaconProxy(
            poolManagerBeacon,
            abi.encodeCall(PoolManager.initialize, (beaconOwner, balanceManagerProxy, orderBookBeacon))
        );
        console.log("PROXY_POOLMANAGER=%s", poolManagerProxy);

        address routerProxy = Upgrades.deployBeaconProxy(
            routerBeacon, abi.encodeCall(GTXRouter.initialize, (poolManagerProxy, balanceManagerProxy))
        );
        console.log("PROXY_ROUTER=%s", routerProxy);

        // Setting up authorizations
        console.log("\n========== CONFIGURING AUTHORIZATIONS ==========");
        BalanceManager balanceManager = BalanceManager(balanceManagerProxy);

        balanceManager.setAuthorizedOperator(address(poolManagerProxy), true);
        console.log("Authorized PoolManager as operator in BalanceManager");

        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        console.log("Authorized Router as operator in BalanceManager");

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Add these to your .env file:");
        console.log("BEACON_BALANCEMANAGER=%s", balanceManagerBeacon);
        console.log("BEACON_POOLMANAGER=%s", poolManagerBeacon);
        console.log("BEACON_ROUTER=%s", routerBeacon);
        console.log("BEACON_ORDERBOOK=%s", orderBookBeacon);
        console.log("PROXY_BALANCEMANAGER=%s", balanceManagerProxy);
        console.log("PROXY_POOLMANAGER=%s", poolManagerProxy);
        console.log("PROXY_ROUTER=%s", routerProxy);

        vm.stopBroadcast();
    }
}
