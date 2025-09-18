// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Script, console} from "forge-std/Script.sol";

import "../src/core/BalanceManager.sol";
import "../src/core/ChainBalanceManager.sol";

/**
 * @title Upgrade GTX Contract
 * @dev Lightning-fast upgrade script for testnet iteration
 * Perfect for accelerator development - upgrade in seconds!
 */
contract UpgradeGTXContract is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconAddress = vm.envAddress("BEACON_ADDRESS");
        string memory contractType = vm.envString("CONTRACT_TYPE"); // "BalanceManager" or "ChainBalanceManager"

        console.log("=== GTX Contract Upgrade (Beacon Pattern) ===");
        console.log("Beacon Address:", beaconAddress);
        console.log("Contract Type:", contractType);
        console.log("Upgrader:", vm.addr(deployerPrivateKey));
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        if (keccak256(bytes(contractType)) == keccak256(bytes("BalanceManager"))) {
            _upgradeBalanceManager(beaconAddress);
        } else if (keccak256(bytes(contractType)) == keccak256(bytes("ChainBalanceManager"))) {
            _upgradeChainBalanceManager(beaconAddress);
        } else {
            revert("Invalid CONTRACT_TYPE. Use 'BalanceManager' or 'ChainBalanceManager'");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("[SUCCESS] Contract upgraded via Beacon!");
        console.log("[INFO] All proxies automatically updated");
        console.log("[READY] Continue development at accelerator pace!");
    }

    function _upgradeBalanceManager(
        address beaconAddress
    ) internal {
        console.log("Upgrading BalanceManager via Beacon...");

        // Deploy new implementation
        BalanceManager newImpl = new BalanceManager();
        console.log("New implementation deployed:", address(newImpl));

        // Get beacon contract
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);

        // Verify current state before upgrade
        console.log("Pre-upgrade verification:");
        address currentImpl = beacon.implementation();
        console.log("  Current implementation:", currentImpl);

        // Perform upgrade
        console.log("Performing upgrade...");
        beacon.upgradeTo(address(newImpl));

        // Verify upgrade success
        console.log("Post-upgrade verification:");
        address newImplAddress = beacon.implementation();
        console.log("  New implementation:", newImplAddress);
        
        if (newImplAddress == address(newImpl)) {
            console.log("[SUCCESS] BalanceManager upgraded successfully");
        } else {
            console.log("[ERROR] Upgrade verification failed");
        }
    }

    function _upgradeChainBalanceManager(
        address beaconAddress
    ) internal {
        console.log("Upgrading ChainBalanceManager via Beacon...");

        // Deploy new implementation
        ChainBalanceManager newImpl = new ChainBalanceManager();
        console.log("New implementation deployed:", address(newImpl));

        // Get beacon contract
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);

        // Verify current state before upgrade
        console.log("Pre-upgrade verification:");
        address currentImpl = beacon.implementation();
        console.log("  Current implementation:", currentImpl);

        // Perform upgrade
        console.log("Performing upgrade...");
        beacon.upgradeTo(address(newImpl));

        // Verify upgrade success
        console.log("Post-upgrade verification:");
        address newImplAddress = beacon.implementation();
        console.log("  New implementation:", newImplAddress);
        
        if (newImplAddress == address(newImpl)) {
            console.log("[SUCCESS] ChainBalanceManager upgraded successfully");
            console.log("[SUCCESS] All proxies using this beacon automatically updated");
        } else {
            console.log("[ERROR] Upgrade verification failed");
        }
    }
}
