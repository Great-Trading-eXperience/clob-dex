// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVault {
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event YieldDeposited(uint256 amount);
    event YieldWithdrawn(uint256 amount);
    event YieldGenerated(uint256 amount);

    // Errors
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error TransferFailed();
    error OnlyChainBalanceManager();

    /// @notice Deposit tokens into the vault
    /// @param amount Amount of tokens to deposit
    function deposit(uint256 amount) external;

    /// @notice Withdraw tokens from the vault
    /// @param amount Amount of tokens to withdraw
    /// @param recipient Address to receive the tokens
    function withdraw(uint256 amount, address recipient) external;

    /// @notice Deposit idle funds into the yield-generating protocol
    /// @param amount Amount to deposit into yield protocol
    function depositToYieldProtocol(uint256 amount) external;

    /// @notice Withdraw funds from the yield-generating protocol
    /// @param amount Amount to withdraw from yield protocol
    function withdrawFromYieldProtocol(uint256 amount) external;

    /// @notice Get total assets in the vault (including yield protocol)
    /// @return Total assets
    function totalAssets() external view returns (uint256);

    /// @notice Get assets in the yield protocol
    /// @return Assets in yield protocol
    function assetsInYieldProtocol() external view returns (uint256);

    /// @notice Get idle assets in the vault
    /// @return Idle assets
    function idleAssets() external view returns (uint256);

    /// @notice Get the underlying asset address
    /// @return Asset address
    function asset() external view returns (address);

    /// @notice Get the ChainBalanceManager address
    /// @return ChainBalanceManager address
    function chainBalanceManager() external view returns (address);
}
