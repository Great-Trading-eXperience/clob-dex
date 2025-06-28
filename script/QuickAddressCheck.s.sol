// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";

contract QuickAddressCheck is Script, DeployHelpers {
    function run() external view {
        console.log("=== NETWORK INFO ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block number:", block.number);
        
        // Get private keys if they exist
        try vm.envUint("PRIVATE_KEY") returns (uint256 privateKey) {
            if (privateKey != 0) {
                address addr = vm.addr(privateKey);
                console.log("Address from PRIVATE_KEY:", addr);
                console.log("ETH balance:", addr.balance);
            }
        } catch {
            console.log("PRIVATE_KEY not set or invalid");
        }
        
        try vm.envUint("PRIVATE_KEY_2") returns (uint256 privateKey2) {
            if (privateKey2 != 0) {
                address addr2 = vm.addr(privateKey2);
                console.log("Address from PRIVATE_KEY_2:", addr2);
                console.log("ETH balance:", addr2.balance);
            }
        } catch {
            console.log("PRIVATE_KEY_2 not set or invalid");
        }
        
        try vm.envAddress("OWNER_ADDRESS") returns (address ownerAddr) {
            console.log("OWNER_ADDRESS from env:", ownerAddr);
            console.log("ETH balance:", ownerAddr.balance);
        } catch {
            console.log("OWNER_ADDRESS not set or invalid");
        }
        
        console.log("msg.sender:", msg.sender);
        console.log("tx.origin:", tx.origin);
        
        // Check deployment file path
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        console.log("Looking for deployments at:", path);
        
        // Check if deployment file exists
        try vm.readFile(path) returns (string memory) {
            console.log("Deployment file exists for chain", chainIdStr);
        } catch {
            console.log("No deployment file found for chain", chainIdStr);
        }
    }
}