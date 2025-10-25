// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../../src/yield/VaultFactory.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title DeployVaults
 * @dev Deploy ERC-4626 vaults for all tokens using VaultFactory
 * Usage: forge script script/yield/DeployVaults.s.sol --broadcast --verify
 */
contract DeployVaults is Script, DeployHelpers {
    string constant VAULT_FACTORY = "VAULT_FACTORY";
    string constant USDC = "MOCK_TOKEN_USDC";
    string constant WETH = "MOCK_TOKEN_WETH";
    string constant WBTC = "MOCK_TOKEN_WBTC";
    string constant USDT = "MOCK_TOKEN_USDT";

    // Vault deployment keys
    string constant VAULT_USDC = "VAULT_USDC";
    string constant VAULT_WETH = "VAULT_WETH";
    string constant VAULT_WBTC = "VAULT_WBTC";
    string constant VAULT_USDT = "VAULT_USDT";

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        loadDeployments();

        // Load VaultFactory
        address vaultFactoryAddr = deployed[VAULT_FACTORY].addr;
        require(vaultFactoryAddr != address(0), "VaultFactory not deployed. Run DeployVaultFactory first.");

        VaultFactory vaultFactory = VaultFactory(vaultFactoryAddr);

        console.log("========== DEPLOYING VAULTS ==========");
        console.log("Deployer:", deployer);
        console.log("VaultFactory:", vaultFactoryAddr);
        console.log("Network:", block.chainid);

        // Get token addresses
        address usdcAddr = deployed[USDC].addr;
        address wethAddr = deployed[WETH].addr;
        address wbtcAddr = deployed[WBTC].addr;
        address usdtAddr = deployed[USDT].addr;

        require(usdcAddr != address(0), "USDC not deployed");
        require(wethAddr != address(0), "WETH not deployed");
        require(wbtcAddr != address(0), "WBTC not deployed");
        require(usdtAddr != address(0), "USDT not deployed");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy vaults individually (can also use deployBatchVaults for gas savings)
        console.log("\n=== Deploying USDC Vault ===");
        address usdcVault = vaultFactory.deploySimpleVault(
            usdcAddr,
            "GTX USDC Yield Vault",
            "gtxUSDC"
        );
        console.log("USDC Vault deployed at:", usdcVault);

        console.log("\n=== Deploying WETH Vault ===");
        address wethVault = vaultFactory.deploySimpleVault(
            wethAddr,
            "GTX WETH Yield Vault",
            "gtxWETH"
        );
        console.log("WETH Vault deployed at:", wethVault);

        console.log("\n=== Deploying WBTC Vault ===");
        address wbtcVault = vaultFactory.deploySimpleVault(
            wbtcAddr,
            "GTX WBTC Yield Vault",
            "gtxWBTC"
        );
        console.log("WBTC Vault deployed at:", wbtcVault);

        console.log("\n=== Deploying USDT Vault ===");
        address usdtVault = vaultFactory.deploySimpleVault(
            usdtAddr,
            "GTX USDT Yield Vault",
            "gtxUSDT"
        );
        console.log("USDT Vault deployed at:", usdtVault);

        vm.stopBroadcast();

        // Save deployments
        deployments.push(Deployment(VAULT_USDC, usdcVault));
        deployments.push(Deployment(VAULT_WETH, wethVault));
        deployments.push(Deployment(VAULT_WBTC, wbtcVault));
        deployments.push(Deployment(VAULT_USDT, usdtVault));

        deployed[VAULT_USDC] = DeployedContract(usdcVault, true);
        deployed[VAULT_WETH] = DeployedContract(wethVault, true);
        deployed[VAULT_WBTC] = DeployedContract(wbtcVault, true);
        deployed[VAULT_USDT] = DeployedContract(usdtVault, true);

        exportDeployments();

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("VAULT_USDC=%s", usdcVault);
        console.log("VAULT_WETH=%s", wethVault);
        console.log("VAULT_WBTC=%s", wbtcVault);
        console.log("VAULT_USDT=%s", usdtVault);
        console.log("\nAll vaults deployed successfully!");
    }

    /**
     * @dev Alternative: Deploy all vaults in one transaction using batch function
     * More gas efficient
     */
    function runBatch() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        loadDeployments();

        address vaultFactoryAddr = deployed[VAULT_FACTORY].addr;
        require(vaultFactoryAddr != address(0), "VaultFactory not deployed");

        VaultFactory vaultFactory = VaultFactory(vaultFactoryAddr);

        // Prepare batch deployment data
        address[] memory assets = new address[](4);
        string[] memory names = new string[](4);
        string[] memory symbols = new string[](4);

        assets[0] = deployed[USDC].addr;
        assets[1] = deployed[WETH].addr;
        assets[2] = deployed[WBTC].addr;
        assets[3] = deployed[USDT].addr;

        names[0] = "GTX USDC Yield Vault";
        names[1] = "GTX WETH Yield Vault";
        names[2] = "GTX WBTC Yield Vault";
        names[3] = "GTX USDT Yield Vault";

        symbols[0] = "gtxUSDC";
        symbols[1] = "gtxWETH";
        symbols[2] = "gtxWBTC";
        symbols[3] = "gtxUSDT";

        console.log("========== BATCH DEPLOYING VAULTS ==========");
        console.log("Deployer:", deployer);
        console.log("VaultFactory:", vaultFactoryAddr);

        vm.startBroadcast(deployerPrivateKey);

        address[] memory vaults = vaultFactory.deployBatchVaults(assets, names, symbols);

        vm.stopBroadcast();

        // Save deployments
        deployments.push(Deployment(VAULT_USDC, vaults[0]));
        deployments.push(Deployment(VAULT_WETH, vaults[1]));
        deployments.push(Deployment(VAULT_WBTC, vaults[2]));
        deployments.push(Deployment(VAULT_USDT, vaults[3]));

        deployed[VAULT_USDC] = DeployedContract(vaults[0], true);
        deployed[VAULT_WETH] = DeployedContract(vaults[1], true);
        deployed[VAULT_WBTC] = DeployedContract(vaults[2], true);
        deployed[VAULT_USDT] = DeployedContract(vaults[3], true);

        exportDeployments();

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        for (uint256 i = 0; i < vaults.length; i++) {
            console.log("Vault", i, "deployed at:", vaults[i]);
        }
    }
}
