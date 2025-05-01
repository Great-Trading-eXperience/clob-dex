// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/PoolManager.sol";
import "./DeployHelpers.s.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract Deploy is DeployHelpers {
    function run() public {
        loadDeployments();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconOwner = getDeployedAddress("OWNER_ADDRESS");
        address feeReceiver = getDeployedAddress("FEE_RECEIVER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy beacons
        console.log("========== DEPLOYING BEACONS ==========");
        address balanceManagerBeacon = Upgrades.deployBeacon("BalanceManager.sol", beaconOwner);
        address poolManagerBeacon = Upgrades.deployBeacon("PoolManager.sol", beaconOwner);
        address routerBeacon = Upgrades.deployBeacon("GTXRouter.sol", beaconOwner);
        address orderBookBeacon = Upgrades.deployBeacon("OrderBook.sol", beaconOwner);

        // Store beacon addresses in deployments array and mapping
        deployments.push(Deployment("BEACON_BALANCEMANAGER", balanceManagerBeacon));
        deployed["BEACON_BALANCEMANAGER"] = DeployedContract(balanceManagerBeacon, true);

        deployments.push(Deployment("BEACON_POOLMANAGER", poolManagerBeacon));
        deployed["BEACON_POOLMANAGER"] = DeployedContract(poolManagerBeacon, true);

        deployments.push(Deployment("BEACON_ROUTER", routerBeacon));
        deployed["BEACON_ROUTER"] = DeployedContract(routerBeacon, true);

        deployments.push(Deployment("BEACON_ORDERBOOK", orderBookBeacon));
        deployed["BEACON_ORDERBOOK"] = DeployedContract(orderBookBeacon, true);

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
                (beaconOwner, feeReceiver, 1, 2) // owner, feeReceiver, feeMaker (0.1%), feeTaker (0.2%)
            )
        );
        address poolManagerProxy = Upgrades.deployBeaconProxy(
            poolManagerBeacon,
            abi.encodeCall(PoolManager.initialize, (beaconOwner, balanceManagerProxy, orderBookBeacon))
        );
        address routerProxy = Upgrades.deployBeaconProxy(
            routerBeacon, abi.encodeCall(GTXRouter.initialize, (poolManagerProxy, balanceManagerProxy))
        );

        // Store proxy addresses in deployments array and mapping
        deployments.push(Deployment("PROXY_BALANCEMANAGER", balanceManagerProxy));
        deployed["PROXY_BALANCEMANAGER"] = DeployedContract(balanceManagerProxy, true);

        deployments.push(Deployment("PROXY_POOLMANAGER", poolManagerProxy));
        deployed["PROXY_POOLMANAGER"] = DeployedContract(poolManagerProxy, true);

        deployments.push(Deployment("PROXY_ROUTER", routerProxy));
        deployed["PROXY_ROUTER"] = DeployedContract(routerProxy, true);

        console.log("PROXY_BALANCEMANAGER=%s", balanceManagerProxy);
        console.log("PROXY_POOLMANAGER=%s", poolManagerProxy);
        console.log("PROXY_ROUTER=%s", routerProxy);

        // Setting up authorizations
        console.log("\n========== CONFIGURING AUTHORIZATIONS ==========");
        BalanceManager balanceManager = BalanceManager(balanceManagerProxy);

        balanceManager.setPoolManager(address(poolManagerProxy));
        console.log("Set PoolManager in BalanceManager");

        balanceManager.setAuthorizedOperator(address(poolManagerProxy), true);
        console.log("Authorized PoolManager as operator in BalanceManager");

        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        console.log("Authorized Router as operator in BalanceManager");

        PoolManager poolManager = PoolManager(poolManagerProxy);
        poolManager.setRouter(routerProxy);
        console.log("Set router in PoolManager");

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Deployment addresses saved to JSON file:");
        console.log("PROXY_BALANCEMANAGER=%s", balanceManagerProxy);
        console.log("PROXY_POOLMANAGER=%s", poolManagerProxy);
        console.log("PROXY_ROUTER=%s", routerProxy);
        console.log("BEACON_ORDERBOOK=%s", orderBookBeacon);
        vm.stopBroadcast();

        // Export deployments to JSON file
        exportDeployments();
    }

    // Helper function to get deployed addresses from mapping or fallback to env var
    function getDeployedAddress(
        string memory key
    ) private view returns (address) {
        // Check if address exists in deployments
        if (deployed[key].isSet) {
            return deployed[key].addr;
        }

        // Fall back to env var
        return vm.envOr(key, address(0));
    }
}
