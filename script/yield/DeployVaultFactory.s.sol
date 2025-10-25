// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../../src/vaults/VaultFactory.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title DeployVaultFactory
 * @dev Deploy the VaultFactory contract
 * Usage: forge script script/yield/DeployVaultFactory.s.sol --broadcast --verify
 */
contract DeployVaultFactory is Script, DeployHelpers {
    string constant VAULT_FACTORY = "VAULT_FACTORY";

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        loadDeployments();

        console.log("========== DEPLOYING VAULT FACTORY ==========");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy VaultFactory
        VaultFactory vaultFactory = new VaultFactory(deployer);

        console.log("VaultFactory deployed at:", address(vaultFactory));

        vm.stopBroadcast();

        // Save deployment
        deployments.push(Deployment(VAULT_FACTORY, address(vaultFactory)));
        deployed[VAULT_FACTORY] = DeployedContract(address(vaultFactory), true);

        exportDeployments();

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("VAULT_FACTORY=%s", address(vaultFactory));
        console.log("Owner:", vaultFactory.owner());
    }
}
