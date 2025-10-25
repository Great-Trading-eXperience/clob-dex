// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../../src/core/ChainBalanceManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title ConfigureVaults
 * @dev Configure ChainBalanceManager with deployed vaults
 * Usage: forge script script/yield/ConfigureVaults.s.sol --broadcast
 */
contract ConfigureVaults is Script, DeployHelpers {
    string constant CHAIN_BALANCE_MANAGER = "PROXY_CHAINBALANCEMANAGER";
    string constant USDC = "MOCK_TOKEN_USDC";
    string constant WETH = "MOCK_TOKEN_WETH";
    string constant WBTC = "MOCK_TOKEN_WBTC";
    string constant USDT = "MOCK_TOKEN_USDT";
    string constant VAULT_USDC = "VAULT_USDC";
    string constant VAULT_WETH = "VAULT_WETH";
    string constant VAULT_WBTC = "VAULT_WBTC";
    string constant VAULT_USDT = "VAULT_USDT";

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        loadDeployments();

        // Load ChainBalanceManager
        address cbmAddr = deployed[CHAIN_BALANCE_MANAGER].addr;
        require(cbmAddr != address(0), "ChainBalanceManager not deployed");

        ChainBalanceManager cbm = ChainBalanceManager(cbmAddr);

        console.log("========== CONFIGURING VAULTS ==========");
        console.log("Deployer:", deployer);
        console.log("ChainBalanceManager:", cbmAddr);

        // Load token and vault addresses
        address usdcAddr = deployed[USDC].addr;
        address wethAddr = deployed[WETH].addr;
        address wbtcAddr = deployed[WBTC].addr;
        address usdtAddr = deployed[USDT].addr;

        address usdcVault = deployed[VAULT_USDC].addr;
        address wethVault = deployed[VAULT_WETH].addr;
        address wbtcVault = deployed[VAULT_WBTC].addr;
        address usdtVault = deployed[VAULT_USDT].addr;

        require(usdcAddr != address(0), "USDC not deployed");
        require(wethAddr != address(0), "WETH not deployed");
        require(wbtcAddr != address(0), "WBTC not deployed");
        require(usdtAddr != address(0), "USDT not deployed");

        require(usdcVault != address(0), "USDC Vault not deployed");
        require(wethVault != address(0), "WETH Vault not deployed");
        require(wbtcVault != address(0), "WBTC Vault not deployed");
        require(usdtVault != address(0), "USDT Vault not deployed");

        vm.startBroadcast(deployerPrivateKey);

        // Set vaults for each token
        console.log("\n=== Setting USDC Vault ===");
        console.log("Token:", usdcAddr);
        console.log("Vault:", usdcVault);
        cbm.setVault(usdcAddr, usdcVault);

        console.log("\n=== Setting WETH Vault ===");
        console.log("Token:", wethAddr);
        console.log("Vault:", wethVault);
        cbm.setVault(wethAddr, wethVault);

        console.log("\n=== Setting WBTC Vault ===");
        console.log("Token:", wbtcAddr);
        console.log("Vault:", wbtcVault);
        cbm.setVault(wbtcAddr, wbtcVault);

        console.log("\n=== Setting USDT Vault ===");
        console.log("Token:", usdtAddr);
        console.log("Vault:", usdtVault);
        cbm.setVault(usdtAddr, usdtVault);

        // Set vault ratio (80%)
        console.log("\n=== Setting Vault Ratio to 80% ===");
        cbm.setVaultRatio(8000); // 80% to vaults, 20% hot reserve

        vm.stopBroadcast();

        // Verify configuration
        console.log("\n========== VERIFICATION ==========");
        console.log("USDC vault configured:", cbm.getVault(usdcAddr) == usdcVault);
        console.log("WETH vault configured:", cbm.getVault(wethAddr) == wethVault);
        console.log("WBTC vault configured:", cbm.getVault(wbtcAddr) == wbtcVault);
        console.log("USDT vault configured:", cbm.getVault(usdtAddr) == usdtVault);
        console.log("Vault ratio:", cbm.getVaultRatio());

        console.log("\nAll vaults configured successfully!");
    }

    /**
     * @dev Add new vault for a specific token
     * Usage: TOKEN_ADDRESS=0x... VAULT_ADDRESS=0x... forge script script/yield/ConfigureVaults.s.sol:ConfigureVaults --sig "addVault()" --broadcast
     */
    function addVault() public {
        uint256 deployerPrivateKey = getDeployerKey();

        loadDeployments();

        address cbmAddr = deployed[CHAIN_BALANCE_MANAGER].addr;
        require(cbmAddr != address(0), "ChainBalanceManager not deployed");

        // Get token and vault from environment
        address token = vm.envAddress("TOKEN_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");

        require(token != address(0), "TOKEN_ADDRESS not set");
        require(vault != address(0), "VAULT_ADDRESS not set");

        console.log("========== ADDING NEW VAULT ==========");
        console.log("Token:", token);
        console.log("Vault:", vault);

        ChainBalanceManager cbm = ChainBalanceManager(cbmAddr);

        vm.startBroadcast(deployerPrivateKey);

        cbm.setVault(token, vault);

        vm.stopBroadcast();

        console.log("Vault configured successfully!");
        console.log("Verify:", cbm.getVault(token) == vault);
    }

    /**
     * @dev Remove vault for a token
     * Usage: TOKEN_ADDRESS=0x... forge script script/yield/ConfigureVaults.s.sol:ConfigureVaults --sig "removeVault()" --broadcast
     */
    function removeVault() public {
        uint256 deployerPrivateKey = getDeployerKey();

        loadDeployments();

        address cbmAddr = deployed[CHAIN_BALANCE_MANAGER].addr;
        require(cbmAddr != address(0), "ChainBalanceManager not deployed");

        address token = vm.envAddress("TOKEN_ADDRESS");
        require(token != address(0), "TOKEN_ADDRESS not set");

        console.log("========== REMOVING VAULT ==========");
        console.log("Token:", token);

        ChainBalanceManager cbm = ChainBalanceManager(cbmAddr);

        vm.startBroadcast(deployerPrivateKey);

        cbm.setVault(token, address(0)); // Set to address(0) to remove

        vm.stopBroadcast();

        console.log("Vault removed successfully!");
        console.log("Verify:", cbm.getVault(token) == address(0));
    }
}
