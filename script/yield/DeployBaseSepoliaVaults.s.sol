// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../../src/vaults/VaultFactory.sol";
import {GTXVault} from "../../src/vaults/GTXVault.sol";

/**
 * @title DeployBaseSepoliaVaults
 * @notice Deploy GTX Vaults on Base Sepolia with Aave V3 integration
 * @dev This script deploys vaults for real Base Sepolia tokens with Aave lending
 *
 * Prerequisites:
 * - VaultFactory must be deployed first
 * - Set PRIVATE_KEY in .env
 * - Set ALCHEMY_API_KEY or BASE_SEPOLIA_RPC in .env
 * - Set BASESCAN_API_KEY for verification
 *
 * Usage:
 *   forge script script/yield/DeployBaseSepoliaVaults.s.sol:DeployBaseSepoliaVaults \
 *     --rpc-url baseSepolia \
 *     --broadcast \
 *     --verify
 *
 * Expected Chain ID: 84532 (Base Sepolia)
 */
contract DeployBaseSepoliaVaults is Script {
    // ========== BASE SEPOLIA TOKEN ADDRESSES ==========
    // Source: https://docs.base.org/tokens/

    address constant USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Circle USDC
    address constant WETH_BASE_SEPOLIA = 0x4200000000000000000000000000000000000006; // Wrapped Ether

    // Note: WBTC and USDT may not be available on Base Sepolia testnet
    // For testing, you can deploy mocks or use alternative tokens
    address constant WBTC_BASE_SEPOLIA = address(0); // To be determined
    address constant USDT_BASE_SEPOLIA = address(0); // To be determined

    // ========== AAVE V3 ON BASE SEPOLIA ==========
    // Aave V3 is not deployed on Base Sepolia testnet
    // For testing, we'll deploy without lending pool initially
    // Or deploy MockLendingPool for testing
    address constant AAVE_POOL_BASE_SEPOLIA = address(0);

    // ========== DEPLOYMENT PARAMETERS ==========
    address public vaultFactory;
    address public chainBalanceManager; // Will be set as vault owner

    struct VaultDeployment {
        address asset;
        string name;
        string symbol;
        address lendingPool;
        address deployedVault;
    }

    VaultDeployment[] public vaults;

    function setUp() public {
        // Load addresses from environment or previous deployments
        vaultFactory = vm.envOr("VAULT_FACTORY_BASE_SEPOLIA", address(0));
        chainBalanceManager = vm.envOr("CHAIN_BALANCE_MANAGER_BASE_SEPOLIA", address(0));

        require(vaultFactory != address(0), "VAULT_FACTORY_BASE_SEPOLIA not set");

        // ChainBalanceManager is optional for initial deployment
        // Can be set later via transferOwnership
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n========== BASE SEPOLIA VAULT DEPLOYMENT ==========");
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 84532, "Must be Base Sepolia (84532)");

        console.log("Deployer:", deployer);
        console.log("VaultFactory:", vaultFactory);
        console.log("ChainBalanceManager:", chainBalanceManager);

        // Owner will be ChainBalanceManager if set, otherwise deployer
        address vaultOwner = chainBalanceManager != address(0) ? chainBalanceManager : deployer;
        console.log("Vault Owner:", vaultOwner);

        // ========== PREPARE VAULT CONFIGURATIONS ==========

        // USDC Vault (primary stablecoin)
        if (USDC_BASE_SEPOLIA != address(0)) {
            vaults.push(VaultDeployment({
                asset: USDC_BASE_SEPOLIA,
                name: "GTX USDC Yield Vault",
                symbol: "gtxUSDC",
                lendingPool: AAVE_POOL_BASE_SEPOLIA, // Will be address(0) initially
                deployedVault: address(0)
            }));
        }

        // WETH Vault
        if (WETH_BASE_SEPOLIA != address(0)) {
            vaults.push(VaultDeployment({
                asset: WETH_BASE_SEPOLIA,
                name: "GTX WETH Yield Vault",
                symbol: "gtxWETH",
                lendingPool: AAVE_POOL_BASE_SEPOLIA,
                deployedVault: address(0)
            }));
        }

        // WBTC Vault (if available)
        if (WBTC_BASE_SEPOLIA != address(0)) {
            vaults.push(VaultDeployment({
                asset: WBTC_BASE_SEPOLIA,
                name: "GTX WBTC Yield Vault",
                symbol: "gtxWBTC",
                lendingPool: AAVE_POOL_BASE_SEPOLIA,
                deployedVault: address(0)
            }));
        }

        // USDT Vault (if available)
        if (USDT_BASE_SEPOLIA != address(0)) {
            vaults.push(VaultDeployment({
                asset: USDT_BASE_SEPOLIA,
                name: "GTX USDT Yield Vault",
                symbol: "gtxUSDT",
                lendingPool: AAVE_POOL_BASE_SEPOLIA,
                deployedVault: address(0)
            }));
        }

        require(vaults.length > 0, "No vaults to deploy");

        console.log("\n=== Prepared vaults for deployment ===");
        console.log("Number of vaults:", vaults.length);

        // ========== DEPLOY VAULTS ==========

        vm.startBroadcast(deployerPrivateKey);

        VaultFactory factory = VaultFactory(vaultFactory);

        for (uint256 i = 0; i < vaults.length; i++) {
            VaultDeployment storage vault = vaults[i];

            console.log("\n=== Deploying Vault ===");
            console.log("Vault number:", i + 1);
            console.log("Asset:", vault.asset);
            console.log("Name:", vault.name);
            console.log("Symbol:", vault.symbol);

            address deployedVault;

            if (vault.lendingPool == address(0)) {
                // Deploy simple vault without lending pool
                console.log("Deploying SIMPLE vault (no lending pool)");
                deployedVault = factory.deploySimpleVault(
                    vault.asset,
                    vault.name,
                    vault.symbol
                );
            } else {
                // Deploy GTX vault with lending pool integration
                console.log("Deploying GTX vault with lending pool:", vault.lendingPool);
                deployedVault = factory.deployGTXVault(
                    vault.asset,
                    vault.name,
                    vault.symbol,
                    vault.lendingPool
                );
            }

            vault.deployedVault = deployedVault;
            console.log("Deployed at:", deployedVault);

            // Transfer ownership to ChainBalanceManager if specified
            if (chainBalanceManager != address(0) && chainBalanceManager != deployer) {
                console.log("Transferring ownership to ChainBalanceManager...");
                GTXVault(deployedVault).transferOwnership(chainBalanceManager);
                console.log("Ownership transferred");
            }
        }

        vm.stopBroadcast();

        // ========== DEPLOYMENT SUMMARY ==========

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Chain ID:", block.chainid);
        console.log("Network: Base Sepolia");
        console.log("VaultFactory:", vaultFactory);
        console.log("\nDeployed Vaults:");

        for (uint256 i = 0; i < vaults.length; i++) {
            VaultDeployment memory vault = vaults[i];
            console.log("\n", vault.symbol);
            console.log("  Asset:", vault.asset);
            console.log("  Vault:", vault.deployedVault);
            console.log("  Owner:", vaultOwner);
        }

        console.log("\n========== ENVIRONMENT VARIABLES ==========");
        console.log("Add these to your .env file:");
        console.log("");

        for (uint256 i = 0; i < vaults.length; i++) {
            VaultDeployment memory vault = vaults[i];
            string memory envVarName = string(abi.encodePacked("VAULT_", vault.symbol, "_BASE_SEPOLIA"));
            console.log("%s=%s", envVarName, vault.deployedVault);
        }

        console.log("\n========== NEXT STEPS ==========");
        console.log("1. Add vault addresses to .env");
        console.log("2. If lending pools available, configure with ConfigureVaults.s.sol");
        console.log("3. Verify contracts on Basescan");
        console.log("4. Configure indexer to track these vaults");
        console.log("5. Test deposits and yield accrual");
        console.log("\nDeployment complete!");
    }

    /**
     * @notice Verify deployment results
     * @dev Call this after deployment to validate vault configuration
     */
    function verify() public view {
        console.log("\n========== VERIFYING DEPLOYMENTS ==========");

        VaultFactory factory = VaultFactory(vaultFactory);

        for (uint256 i = 0; i < vaults.length; i++) {
            VaultDeployment memory vault = vaults[i];

            console.log("\nVerifying:", vault.symbol);

            // Check vault registered in factory
            address registeredVault = factory.getVault(vault.asset);
            require(registeredVault == vault.deployedVault, "Vault not registered in factory");
            console.log("  [OK] Registered in factory");

            // Check vault properties
            GTXVault gtxVault = GTXVault(vault.deployedVault);
            require(gtxVault.asset() == vault.asset, "Asset mismatch");
            console.log("  [OK] Asset configured correctly");

            address vaultOwner = gtxVault.owner();
            console.log("  [OK] Owner:", vaultOwner);

            address lendingPool = gtxVault.lendingPool();
            console.log("  [OK] Lending Pool:", lendingPool);
        }

        console.log("\nAll verifications passed!");
    }
}
