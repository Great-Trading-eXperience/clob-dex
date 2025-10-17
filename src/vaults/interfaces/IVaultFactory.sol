// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVaultFactory {
    // Events
    event VaultCreated(address indexed asset, address indexed vault);

    // Errors
    error VaultAlreadyExists();
    error ZeroAddress();

    /// @notice Create a new vault for an asset
    /// @param asset The underlying asset for the vault
    /// @param lendingPool The lending pool to use for yield generation
    /// @return vault The address of the created vault
    function createVault(address asset, address lendingPool) external returns (address vault);

    /// @notice Get the vault for a specific asset
    /// @param asset The asset to get the vault for
    /// @return vault The vault address (address(0) if not exists)
    function getVault(address asset) external view returns (address vault);

    /// @notice Check if a vault exists for an asset
    /// @param asset The asset to check
    /// @return exists True if vault exists
    function vaultExists(address asset) external view returns (bool exists);

    /// @notice Get all created vaults
    /// @return vaults Array of vault addresses
    function getAllVaults() external view returns (address[] memory vaults);
}
