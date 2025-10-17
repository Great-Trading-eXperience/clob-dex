// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IVault} from "./interfaces/IVault.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";

/**
 * @title Vault
 * @notice A vault contract that holds assets and can deploy them to lending pools for yield generation
 * @dev This contract is controlled by ChainBalanceManager and handles single-asset vaults
 */
contract Vault is IVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The underlying asset this vault holds
    address public immutable asset;

    /// @notice The ChainBalanceManager that controls this vault
    address public immutable chainBalanceManager;

    /// @notice The lending pool for yield generation
    address public lendingPool;

    /// @notice Total assets deposited by ChainBalanceManager
    uint256 public totalDeposits;

    /// @notice Assets currently deposited in the yield protocol
    uint256 public assetsInYield;

    modifier onlyChainBalanceManager() {
        if (msg.sender != chainBalanceManager) {
            revert OnlyChainBalanceManager();
        }
        _;
    }

    /**
     * @notice Constructor
     * @param _asset The underlying asset address
     * @param _chainBalanceManager The ChainBalanceManager address
     * @param _lendingPool The lending pool address for yield generation
     */
    constructor(address _asset, address _chainBalanceManager, address _lendingPool) {
        if (_asset == address(0)) revert ZeroAddress();
        if (_chainBalanceManager == address(0)) revert ZeroAddress();
        if (_lendingPool == address(0)) revert ZeroAddress();

        asset = _asset;
        chainBalanceManager = _chainBalanceManager;
        lendingPool = _lendingPool;
    }

    /**
     * @notice Deposit tokens into the vault
     * @dev Only callable by ChainBalanceManager
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override onlyChainBalanceManager nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Transfer tokens from ChainBalanceManager to this vault
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        totalDeposits += amount;

        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Withdraw tokens from the vault
     * @dev Only callable by ChainBalanceManager
     * @param amount Amount of tokens to withdraw
     * @param recipient Address to receive the tokens
     */
    function withdraw(uint256 amount, address recipient) external override onlyChainBalanceManager nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        uint256 idle = idleAssets();

        // If we don't have enough idle assets, withdraw from yield protocol
        if (idle < amount) {
            uint256 needed = amount - idle;
            _withdrawFromYieldProtocol(needed);
        }

        totalDeposits -= amount;

        // Transfer tokens to recipient
        IERC20(asset).safeTransfer(recipient, amount);

        emit Withdraw(recipient, amount);
    }

    /**
     * @notice Deposit idle funds into the yield-generating protocol
     * @dev Only callable by ChainBalanceManager during rebalancing
     * @param amount Amount to deposit into yield protocol
     */
    function depositToYieldProtocol(uint256 amount) external override onlyChainBalanceManager nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 idle = idleAssets();
        if (idle < amount) revert InsufficientBalance();

        _depositToYieldProtocol(amount);

        emit YieldDeposited(amount);
    }

    /**
     * @notice Withdraw funds from the yield-generating protocol
     * @dev Only callable by ChainBalanceManager during rebalancing
     * @param amount Amount to withdraw from yield protocol
     */
    function withdrawFromYieldProtocol(uint256 amount) external override onlyChainBalanceManager nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (assetsInYield < amount) revert InsufficientBalance();

        _withdrawFromYieldProtocol(amount);

        emit YieldWithdrawn(amount);
    }

    /**
     * @notice Internal function to deposit to yield protocol
     * @param amount Amount to deposit
     */
    function _depositToYieldProtocol(uint256 amount) internal {
        // Approve lending pool to spend tokens
        IERC20(asset).safeIncreaseAllowance(lendingPool, amount);

        // Deposit into lending pool
        ILendingPool(lendingPool).deposit(asset, amount, address(this));

        assetsInYield += amount;
    }

    /**
     * @notice Internal function to withdraw from yield protocol
     * @param amount Amount to withdraw
     */
    function _withdrawFromYieldProtocol(uint256 amount) internal {
        // Get actual balance in lending pool (includes yield)
        uint256 poolBalance = ILendingPool(lendingPool).balanceOf(asset, address(this));

        // Determine how much to withdraw
        uint256 toWithdraw;
        if (amount >= assetsInYield) {
            // If requesting all or more than tracked principal, withdraw everything (principal + yield)
            toWithdraw = poolBalance;
        } else {
            // If requesting less than principal, withdraw exact amount requested
            toWithdraw = amount > poolBalance ? poolBalance : amount;
        }

        // Withdraw from lending pool
        uint256 withdrawn = ILendingPool(lendingPool).withdraw(asset, toWithdraw, address(this));

        // Update assetsInYield tracking
        // If we withdrew more than tracked (due to yield), update accordingly
        if (withdrawn >= assetsInYield) {
            // We got back all principal + yield
            assetsInYield = 0;
        } else {
            // We only withdrew part of the principal
            assetsInYield -= withdrawn;
        }
    }

    /**
     * @notice Get total assets in the vault (including yield protocol)
     * @return Total assets
     */
    function totalAssets() external view override returns (uint256) {
        // Get actual balance in lending pool (includes yield)
        uint256 poolBalance = ILendingPool(lendingPool).balanceOf(asset, address(this));

        // Total = idle assets + actual pool balance (with yield)
        return IERC20(asset).balanceOf(address(this)) + poolBalance;
    }

    /**
     * @notice Get assets in the yield protocol
     * @return Assets in yield protocol
     */
    function assetsInYieldProtocol() external view override returns (uint256) {
        return assetsInYield;
    }

    /**
     * @notice Get idle assets in the vault (not in yield protocol)
     * @return Idle assets
     */
    function idleAssets() public view override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
}
