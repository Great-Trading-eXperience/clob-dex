// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {TokenRegistry} from "../../src/core/TokenRegistry.sol";

/**
 * @title DeployTokenRegistry
 * @dev Script to deploy TokenRegistry with Beacon Proxy pattern
 */
contract DeployTokenRegistry is Script {
    
    function run() external {
        address owner = msg.sender;
        
        vm.startBroadcast();
        
        console.log("Deploying TokenRegistry...");
        console.log("Owner:", owner);
        
        // Deploy implementation
        address implementation = address(new TokenRegistry());
        console.log("Implementation deployed at:", implementation);
        
        // Deploy beacon
        UpgradeableBeacon beacon = new UpgradeableBeacon(implementation, owner);
        console.log("Beacon deployed at:", address(beacon));
        
        // Deploy proxy
        BeaconProxy proxy = new BeaconProxy(
            address(beacon),
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        console.log("Proxy deployed at:", address(proxy));
        
        vm.stopBroadcast();
        
        // Verify deployment
        TokenRegistry tokenRegistry = TokenRegistry(address(proxy));
        console.log("TokenRegistry owner:", tokenRegistry.owner());
        
        // Test default mappings
        address synthetiUSDC = tokenRegistry.getSyntheticToken(4661, 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, 1918988905);
        console.log("Default USDC mapping:", synthetiUSDC);
        
        console.log("\nTokenRegistry deployment complete!");
    }
}