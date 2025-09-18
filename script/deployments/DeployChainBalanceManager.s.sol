// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/core/ChainBalanceManager.sol";
import "./DeployHelpers.s.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployChainBalanceManager is DeployHelpers {
    // Contract address keys
    string constant BEACON_CHAINBALANCEMANAGER = "BEACON_CHAINBALANCEMANAGER";
    string constant PROXY_CHAINBALANCEMANAGER = "PROXY_CHAINBALANCEMANAGER";
    string constant OWNER_ADDRESS = "OWNER_ADDRESS";

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadDeployments();
        
        address beaconOwner;
        if (deployed[OWNER_ADDRESS].isSet) {
            beaconOwner = deployed[OWNER_ADDRESS].addr;
        } else {
            beaconOwner = vm.addr(deployerPrivateKey);
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ChainBalanceManager implementation
        console.log("========== DEPLOYING CHAIN BALANCE MANAGER IMPLEMENTATION ==========");
        ChainBalanceManager implementation = new ChainBalanceManager();
        console.log("ChainBalanceManager Implementation deployed at:", address(implementation));

        // Deploy beacon
        console.log("\n========== DEPLOYING CHAIN BALANCE MANAGER BEACON ==========");
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), beaconOwner);
        address chainBalanceManagerBeacon = address(beacon);

        // Always update the deployment records with new addresses
        deployments.push(Deployment(BEACON_CHAINBALANCEMANAGER, chainBalanceManagerBeacon));
        deployed[BEACON_CHAINBALANCEMANAGER] = DeployedContract(chainBalanceManagerBeacon, true);

        // Deploy proxy
        console.log("\n========== DEPLOYING CHAIN BALANCE MANAGER PROXY ==========");
        bytes memory initData = abi.encodeWithSignature("initialize(address)", beaconOwner);
        BeaconProxy proxy = new BeaconProxy(chainBalanceManagerBeacon, initData);
        address chainBalanceManagerProxy = address(proxy);

        // Always update the deployment records with new addresses
        deployments.push(Deployment(PROXY_CHAINBALANCEMANAGER, chainBalanceManagerProxy));
        deployed[PROXY_CHAINBALANCEMANAGER] = DeployedContract(chainBalanceManagerProxy, true);

        console.log("BEACON_CHAINBALANCEMANAGER=%s", chainBalanceManagerBeacon);
        console.log("PROXY_CHAINBALANCEMANAGER=%s", chainBalanceManagerProxy);

        vm.stopBroadcast();
        
        // Save deployments to JSON
        exportDeployments();
        
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Deployment addresses saved to JSON file:");
        console.log("BEACON_CHAINBALANCEMANAGER=%s", chainBalanceManagerBeacon);
        console.log("PROXY_CHAINBALANCEMANAGER=%s", chainBalanceManagerProxy);
        console.log("Owner: %s", beaconOwner);
    }

    function deployStandalone() public returns (address) {
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("========== DEPLOYING STANDALONE CHAIN BALANCE MANAGER ==========");
        console.log("Owner will be:", owner);

        // Deploy implementation
        ChainBalanceManager implementation = new ChainBalanceManager();
        console.log("Implementation deployed at:", address(implementation));

        // Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(implementation), owner);
        console.log("Beacon deployed at:", address(beacon));

        // Deploy proxy
        bytes memory initData = abi.encodeWithSignature("initialize(address)", owner);
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        console.log("Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        return address(proxy);
    }
}