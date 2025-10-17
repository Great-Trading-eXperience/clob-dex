// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {Vault} from "./Vault.sol";

/**
 * @title VaultFactory
 * @notice Factory contract for creating asset-specific vaults
 * @dev Only the owner (ChainBalanceManager) can create vaults
 */
contract VaultFactory is IVaultFactory, Ownable {
    /// @notice Mapping of asset address to vault address
    mapping(address => address) public vaults;

    /// @notice Array of all vault addresses
    address[] public allVaults;

    /// @notice The ChainBalanceManager address
    address public immutable chainBalanceManager;

    /**
     * @notice Constructor
     * @param _chainBalanceManager The ChainBalanceManager address that will own this factory
     */
    constructor(address _chainBalanceManager) Ownable(_chainBalanceManager) {
        if (_chainBalanceManager == address(0)) revert ZeroAddress();
        chainBalanceManager = _chainBalanceManager;
    }

    /**
     * @notice Create a new vault for an asset
     * @dev Only callable by owner (ChainBalanceManager)
     * @param asset The underlying asset for the vault
     * @param lendingPool The lending pool to use for yield generation
     * @return vault The address of the created vault
     */
    function createVault(address asset, address lendingPool) external onlyOwner returns (address vault) {
        if (asset == address(0)) revert ZeroAddress();
        if (lendingPool == address(0)) revert ZeroAddress();
        if (vaults[asset] != address(0)) revert VaultAlreadyExists();

        // Deploy new vault
        vault = address(new Vault(asset, chainBalanceManager, lendingPool));

        // Store vault address
        vaults[asset] = vault;
        allVaults.push(vault);

        emit VaultCreated(asset, vault);

        return vault;
    }

    /**
     * @notice Get the vault for a specific asset
     * @param asset The asset to get the vault for
     * @return vault The vault address (address(0) if not exists)
     */
    function getVault(address asset) external view returns (address vault) {
        return vaults[asset];
    }

    /**
     * @notice Check if a vault exists for an asset
     * @param asset The asset to check
     * @return exists True if vault exists
     */
    function vaultExists(address asset) external view returns (bool exists) {
        return vaults[asset] != address(0);
    }

    /**
     * @notice Get all created vaults
     * @return Array of vault addresses
     */
    function getAllVaults() external view returns (address[] memory) {
        return allVaults;
    }

    /**
     * @notice Get the total number of vaults
     * @return The number of vaults
     */
    function vaultCount() external view returns (uint256) {
        return allVaults.length;
    }
}
