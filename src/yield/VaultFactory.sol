// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title SimpleERC4626Vault
 * @dev Basic ERC-4626 compliant vault for yield generation
 * In production, use real yield strategies (Aave, Compound, etc.)
 */
contract SimpleERC4626Vault is ERC4626, Ownable {
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(owner_) {}

    /**
     * @dev Simulate yield by allowing owner to deposit additional assets
     * In production, this would be yield from lending protocols
     */
    function addYield(uint256 amount) external {
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
        // Yield automatically reflected in totalAssets()
    }

    /**
     * @dev Emergency withdraw (owner only)
     */
    function emergencyWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        IERC20(token).transfer(recipient, amount);
    }
}

/**
 * @title VaultFactory
 * @dev Factory for deploying ERC-4626 vaults for GTX yield system
 * Follows DRY principle: same factory deploys all vaults
 */
contract VaultFactory is Ownable {
    // Events
    event VaultDeployed(
        address indexed asset,
        address indexed vault,
        string name,
        string symbol,
        address deployer
    );

    event VaultStrategySet(address indexed vault, string strategy);

    // Deployed vaults registry
    mapping(address => address) public vaults; // asset => vault
    address[] public allVaults;

    // Supported strategies
    enum Strategy {
        SIMPLE,      // Simple vault (for testing)
        AAVE_V3,     // Aave V3 lending
        COMPOUND_V3, // Compound V3 lending
        YEARN_V3     // Yearn V3 strategies
    }

    constructor(address owner_) Ownable(owner_) {}

    /**
     * @dev Deploy a simple ERC-4626 vault (for testing or simple yield)
     * @param asset The underlying asset (USDC, WETH, etc.)
     * @param name Vault name (e.g., "GTX USDC Vault")
     * @param symbol Vault symbol (e.g., "gtxUSDC")
     * @return vault Address of deployed vault
     */
    function deploySimpleVault(
        address asset,
        string memory name,
        string memory symbol
    ) external onlyOwner returns (address vault) {
        require(vaults[asset] == address(0), "Vault already exists for this asset");

        SimpleERC4626Vault newVault = new SimpleERC4626Vault(
            IERC20(asset),
            name,
            symbol,
            owner()
        );

        vault = address(newVault);
        vaults[asset] = vault;
        allVaults.push(vault);

        emit VaultDeployed(asset, vault, name, symbol, msg.sender);
        emit VaultStrategySet(vault, "SIMPLE");

        return vault;
    }

    /**
     * @dev Deploy vaults for multiple assets at once (gas efficient)
     * @param assets Array of asset addresses
     * @param names Array of vault names
     * @param symbols Array of vault symbols
     * @return deployedVaults Array of deployed vault addresses
     */
    function deployBatchVaults(
        address[] calldata assets,
        string[] calldata names,
        string[] calldata symbols
    ) external onlyOwner returns (address[] memory deployedVaults) {
        require(
            assets.length == names.length && names.length == symbols.length,
            "Array length mismatch"
        );

        deployedVaults = new address[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            require(vaults[assets[i]] == address(0), "Vault already exists");

            SimpleERC4626Vault newVault = new SimpleERC4626Vault(
                IERC20(assets[i]),
                names[i],
                symbols[i],
                owner()
            );

            address vaultAddr = address(newVault);
            vaults[assets[i]] = vaultAddr;
            allVaults.push(vaultAddr);
            deployedVaults[i] = vaultAddr;

            emit VaultDeployed(assets[i], vaultAddr, names[i], symbols[i], msg.sender);
            emit VaultStrategySet(vaultAddr, "SIMPLE");
        }

        return deployedVaults;
    }

    /**
     * @dev Get vault address for an asset
     * @param asset The asset address
     * @return vault The vault address (address(0) if not deployed)
     */
    function getVault(address asset) external view returns (address vault) {
        return vaults[asset];
    }

    /**
     * @dev Get all deployed vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /**
     * @dev Get number of deployed vaults
     * @return count Number of vaults
     */
    function getVaultCount() external view returns (uint256 count) {
        return allVaults.length;
    }

    /**
     * @dev Check if vault exists for asset
     * @param asset The asset address
     * @return exists True if vault exists
     */
    function hasVault(address asset) external view returns (bool exists) {
        return vaults[asset] != address(0);
    }

    /**
     * @dev Get vault info
     * @param asset The asset address
     * @return vault Vault address
     * @return name Vault name
     * @return symbol Vault symbol
     * @return totalAssets Total assets in vault
     * @return totalSupply Total vault shares
     */
    function getVaultInfo(address asset) external view returns (
        address vault,
        string memory name,
        string memory symbol,
        uint256 totalAssets,
        uint256 totalSupply
    ) {
        vault = vaults[asset];
        require(vault != address(0), "Vault does not exist");

        IERC4626 erc4626 = IERC4626(vault);
        name = ERC20(vault).name();
        symbol = ERC20(vault).symbol();
        totalAssets = erc4626.totalAssets();
        totalSupply = erc4626.totalSupply();

        return (vault, name, symbol, totalAssets, totalSupply);
    }
}
