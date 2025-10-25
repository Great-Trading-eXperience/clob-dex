// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GTXVault} from "./GTXVault.sol";

/**
 * @title VaultFactory
 * @notice Factory for deploying ERC-4626 vaults with flexible yield strategies
 * @dev Supports both simple vaults (testing) and GTXVaults (production with lending pools)
 */
contract VaultFactory is Ownable {
    // ========== EVENTS ==========

    event VaultDeployed(
        address indexed asset,
        address indexed vault,
        string name,
        string symbol,
        address indexed lendingPool,
        string strategy
    );

    // ========== STATE VARIABLES ==========

    /// @notice Mapping of asset to deployed vault address
    mapping(address => address) public vaults;

    /// @notice Array of all deployed vaults
    address[] public allVaults;

    /// @notice Supported strategies
    enum Strategy {
        SIMPLE,      // Simple vault (for testing, no lending pool)
        GTX,         // GTX vault with custom lending pool
        AAVE_V3,     // Future: Aave V3 lending
        COMPOUND_V3  // Future: Compound V3 lending
    }

    // ========== CONSTRUCTOR ==========

    constructor(address owner_) Ownable(owner_) {}

    // ========== DEPLOYMENT FUNCTIONS ==========

    /**
     * @notice Deploy a GTX vault with lending pool integration
     * @param asset The underlying asset (USDC, WETH, WBTC, USDT)
     * @param name Vault name (e.g., "GTX USDC Vault")
     * @param symbol Vault symbol (e.g., "gtxUSDC")
     * @param lendingPool The lending pool address (Aave, Compound, etc.)
     * @return vault Address of deployed vault
     */
    function deployGTXVault(
        address asset,
        string memory name,
        string memory symbol,
        address lendingPool
    ) external onlyOwner returns (address vault) {
        require(vaults[asset] == address(0), "Vault already exists for this asset");
        require(asset != address(0), "Invalid asset address");

        GTXVault newVault = new GTXVault(
            IERC20(asset),
            name,
            symbol,
            owner(), // ChainBalanceManager will be owner
            lendingPool
        );

        vault = address(newVault);
        vaults[asset] = vault;
        allVaults.push(vault);

        emit VaultDeployed(asset, vault, name, symbol, lendingPool, "GTX");

        return vault;
    }

    /**
     * @notice Deploy a simple GTX vault without lending pool (for testing)
     * @param asset The underlying asset
     * @param name Vault name
     * @param symbol Vault symbol
     * @return vault Address of deployed vault
     */
    function deploySimpleVault(
        address asset,
        string memory name,
        string memory symbol
    ) external onlyOwner returns (address vault) {
        require(vaults[asset] == address(0), "Vault already exists for this asset");
        require(asset != address(0), "Invalid asset address");

        // Deploy GTXVault with lendingPool = address(0) for testing
        GTXVault newVault = new GTXVault(
            IERC20(asset),
            name,
            symbol,
            owner(),
            address(0) // No lending pool for simple vault
        );

        vault = address(newVault);
        vaults[asset] = vault;
        allVaults.push(vault);

        emit VaultDeployed(asset, vault, name, symbol, address(0), "SIMPLE");

        return vault;
    }

    /**
     * @notice Deploy vaults for multiple assets at once (gas efficient)
     * @param assets Array of asset addresses
     * @param names Array of vault names
     * @param symbols Array of vault symbols
     * @param lendingPools Array of lending pool addresses (use address(0) for simple vaults)
     * @return deployedVaults Array of deployed vault addresses
     */
    function deployBatchVaults(
        address[] calldata assets,
        string[] calldata names,
        string[] calldata symbols,
        address[] calldata lendingPools
    ) external onlyOwner returns (address[] memory deployedVaults) {
        require(
            assets.length == names.length &&
            names.length == symbols.length &&
            symbols.length == lendingPools.length,
            "Array length mismatch"
        );

        deployedVaults = new address[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            require(vaults[assets[i]] == address(0), "Vault already exists");
            require(assets[i] != address(0), "Invalid asset address");

            GTXVault newVault = new GTXVault(
                IERC20(assets[i]),
                names[i],
                symbols[i],
                owner(),
                lendingPools[i]
            );

            address vaultAddr = address(newVault);
            vaults[assets[i]] = vaultAddr;
            allVaults.push(vaultAddr);
            deployedVaults[i] = vaultAddr;

            string memory strategy = lendingPools[i] == address(0) ? "SIMPLE" : "GTX";
            emit VaultDeployed(assets[i], vaultAddr, names[i], symbols[i], lendingPools[i], strategy);
        }

        return deployedVaults;
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get vault address for an asset
     * @param asset The asset address
     * @return vault The vault address (address(0) if not deployed)
     */
    function getVault(address asset) external view returns (address vault) {
        return vaults[asset];
    }

    /**
     * @notice Get all deployed vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /**
     * @notice Get number of deployed vaults
     * @return count Number of vaults
     */
    function getVaultCount() external view returns (uint256 count) {
        return allVaults.length;
    }

    /**
     * @notice Check if vault exists for asset
     * @param asset The asset address
     * @return exists True if vault exists
     */
    function hasVault(address asset) external view returns (bool exists) {
        return vaults[asset] != address(0);
    }

    /**
     * @notice Get comprehensive vault information
     * @param asset The asset address
     * @return vault Vault address
     * @return name Vault name
     * @return symbol Vault symbol
     * @return totalAssets Total assets in vault (including yield)
     * @return totalSupply Total vault shares
     * @return assetsPerShare Current value of 1 share in underlying assets
     */
    function getVaultInfo(address asset) external view returns (
        address vault,
        string memory name,
        string memory symbol,
        uint256 totalAssets,
        uint256 totalSupply,
        uint256 assetsPerShare
    ) {
        vault = vaults[asset];
        require(vault != address(0), "Vault does not exist");

        IERC4626 erc4626 = IERC4626(vault);
        name = ERC20(vault).name();
        symbol = ERC20(vault).symbol();
        totalAssets = erc4626.totalAssets();
        totalSupply = erc4626.totalSupply();

        // Calculate assets per share (1e18 precision)
        if (totalSupply > 0) {
            assetsPerShare = (totalAssets * 1e18) / totalSupply;
        } else {
            assetsPerShare = 1e18; // 1:1 when no shares exist
        }

        return (vault, name, symbol, totalAssets, totalSupply, assetsPerShare);
    }
}
