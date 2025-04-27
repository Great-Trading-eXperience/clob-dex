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

        address balanceManagerBeacon = Upgrades.deployBeacon("BalanceManager.sol", beaconOwner);
        address poolManagerBeacon = Upgrades.deployBeacon("PoolManager.sol", beaconOwner);
        address routerBeacon = Upgrades.deployBeacon("GTXRouter.sol", beaconOwner);
        address orderBookBeacon = Upgrades.deployBeacon("OrderBook.sol", beaconOwner);

        console.log("BalanceManager Beacon deployed at:", balanceManagerBeacon);
        console.log("PoolManager Beacon deployed at:", poolManagerBeacon);
        console.log("Router Beacon deployed at:", routerBeacon);
        console.log("OrderBook Beacon deployed at:", orderBookBeacon);

        // Deploy proxies for each contract
        address balanceManagerProxy = Upgrades.deployBeaconProxy(
            balanceManagerBeacon,
            abi.encodeCall(
                BalanceManager.initialize,
                (beaconOwner, feeReceiver, 1, 5) // owner, feeReceiver, feeMaker (0.1%), feeTaker (0.5%)
            )
        );
        console.log("BalanceManager Proxy deployed at:", balanceManagerProxy);

        address poolManagerProxy = Upgrades.deployBeaconProxy(
            poolManagerBeacon,
            abi.encodeCall(PoolManager.initialize, (beaconOwner, balanceManagerProxy, orderBookBeacon))
        );
        console.log("PoolManager Proxy deployed at:", poolManagerProxy);

        address routerProxy = Upgrades.deployBeaconProxy(
            routerBeacon, abi.encodeCall(GTXRouter.initialize, (poolManagerProxy, balanceManagerProxy))
        );
        console.log("Router Proxy deployed at:", routerProxy);

        // Connect contracts
        BalanceManager balanceManager = BalanceManager(balanceManagerProxy);
        PoolManager poolManager = PoolManager(poolManagerProxy);

        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(routerProxy));

        vm.stopBroadcast();
    }
}
