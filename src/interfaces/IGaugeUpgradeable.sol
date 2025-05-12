// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/// @title IGaugeUpgradeable
/// @notice Extended Gauge interface for upgradeable Gauge module
interface IGaugeUpgradeable {
    /// @notice Returns total active staked supply
    function totalActiveSupply() external view returns (uint256);

    /// @notice Returns a user’s active staked balance
    function activeBalance(address user) external view returns (uint256);

    /// @notice Redeem accumulated rewards for a user
    /// @param user Address of the user
    event RedeemRewards(address indexed user, uint256[] rewardsOut);
}
