// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMintable {
    function mint(address account, uint256 amount) external;
}

/**
 * @title MockLendingPool
 * @notice Mock implementation of a lending pool for testing vault yield generation
 * @dev Simulates a simple lending pool with APY and mints tokens to simulate yield
 */
contract MockLendingPool {
    using SafeERC20 for IERC20;

    // User balances: asset => user => balance
    mapping(address => mapping(address => uint256)) public balances;

    // Total deposited per asset
    mapping(address => uint256) public totalDeposited;

    // APY rate (in basis points, e.g., 500 = 5%)
    uint256 public apyRate = 500; // 5% APY by default

    // Last accrual timestamp per asset per user
    mapping(address => mapping(address => uint256)) public lastAccrualTime;

    // Events
    event Deposit(address indexed asset, address indexed user, uint256 amount);
    event Withdraw(address indexed asset, address indexed user, uint256 amount);
    event YieldAccrued(address indexed asset, address indexed user, uint256 yield);

    /**
     * @notice Deposit tokens into the lending pool
     * @param asset The asset to deposit
     * @param amount The amount to deposit
     * @param onBehalfOf The address that will receive credit
     */
    function deposit(address asset, uint256 amount, address onBehalfOf) external {
        require(amount > 0, "Amount must be > 0");
        require(onBehalfOf != address(0), "Invalid recipient");

        // Accrue yield before updating balance
        _accrueYield(asset, onBehalfOf);

        // Transfer tokens from sender to this contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Update balances
        balances[asset][onBehalfOf] += amount;
        totalDeposited[asset] += amount;

        // Update last accrual time
        lastAccrualTime[asset][onBehalfOf] = block.timestamp;

        emit Deposit(asset, onBehalfOf, amount);
    }

    /**
     * @notice Withdraw tokens from the lending pool
     * @param asset The asset to withdraw
     * @param amount The amount to withdraw
     * @param to The address that will receive the tokens
     * @return The final amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        require(to != address(0), "Invalid recipient");

        // Accrue yield before withdrawing
        _accrueYield(asset, msg.sender);

        uint256 userBalance = balances[asset][msg.sender];
        require(userBalance >= amount, "Insufficient balance");

        // Update balances
        balances[asset][msg.sender] -= amount;
        totalDeposited[asset] -= amount;

        // Transfer tokens to recipient
        IERC20(asset).safeTransfer(to, amount);

        emit Withdraw(asset, msg.sender, amount);

        return amount;
    }

    /**
     * @notice Get the balance of a user in the lending pool (including accrued yield)
     * @param asset The asset to check
     * @param user The user to check
     * @return The balance including accrued yield
     */
    function balanceOf(address asset, address user) external view returns (uint256) {
        uint256 currentBalance = balances[asset][user];
        uint256 accruedYield = _calculateYield(asset, user);
        return currentBalance + accruedYield;
    }

    /**
     * @notice Set the APY rate for yield generation
     * @param newRate New APY in basis points (e.g., 500 = 5%)
     */
    function setAPY(uint256 newRate) external {
        require(newRate <= 10000, "APY too high"); // Max 100%
        apyRate = newRate;
    }

    /**
     * @notice Manually accrue yield for a user (for testing)
     * @param asset The asset
     * @param user The user
     */
    function accrueYield(address asset, address user) external {
        _accrueYield(asset, user);
    }

    /**
     * @notice Internal function to accrue yield
     * @param asset The asset
     * @param user The user
     */
    function _accrueYield(address asset, address user) internal {
        if (balances[asset][user] == 0) {
            lastAccrualTime[asset][user] = block.timestamp;
            return;
        }

        uint256 yield = _calculateYield(asset, user);

        if (yield > 0) {
            balances[asset][user] += yield;
            lastAccrualTime[asset][user] = block.timestamp;
            emit YieldAccrued(asset, user, yield);
        }
    }

    /**
     * @notice Calculate accrued yield for a user
     * @param asset The asset
     * @param user The user
     * @return The accrued yield
     */
    function _calculateYield(address asset, address user) internal view returns (uint256) {
        uint256 balance = balances[asset][user];
        if (balance == 0) return 0;

        uint256 lastAccrual = lastAccrualTime[asset][user];
        if (lastAccrual == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastAccrual;
        if (timeElapsed == 0) return 0;

        // Simple interest: yield = balance * APY * time / (365 days * 10000)
        // APY is in basis points (e.g., 500 = 5%)
        uint256 yield = (balance * apyRate * timeElapsed) / (365 days * 10000);

        return yield;
    }
}
