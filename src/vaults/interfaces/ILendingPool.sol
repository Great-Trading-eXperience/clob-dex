// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ILendingPool {
    /// @notice Deposit tokens into the lending pool
    /// @param asset The asset to deposit
    /// @param amount The amount to deposit
    /// @param onBehalfOf The address that will receive the aTokens
    function deposit(address asset, uint256 amount, address onBehalfOf) external;

    /// @notice Withdraw tokens from the lending pool
    /// @param asset The asset to withdraw
    /// @param amount The amount to withdraw
    /// @param to The address that will receive the tokens
    /// @return The final amount withdrawn
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /// @notice Get the balance of a user in the lending pool
    /// @param asset The asset to check
    /// @param user The user to check
    /// @return The balance
    function balanceOf(address asset, address user) external view returns (uint256);
}
