// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ILendingPool} from "./interfaces/ILendingPool.sol";

/**
 * @title GTXVault
 * @notice Hybrid ERC4626 vault with custom yield strategy integration
 * @dev Combines ERC4626 standard for DeFi composability with custom ILendingPool integration
 *      for flexible yield strategies (Aave, Compound, etc.)
 *
 * Key Features:
 * - ERC4626 compliant for share tracking and DeFi integration
 * - Custom rebalancing between idle reserves and lending pools
 * - Owner-controlled yield strategy management
 * - Gas-efficient yield tracking via shares
 */
contract GTXVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ========== STATE VARIABLES ==========

    /// @notice The lending pool for yield generation (Aave, Compound, etc.)
    address public lendingPool;

    /// @notice Assets currently deposited in the yield protocol
    uint256 public assetsInYield;

    // ========== EVENTS ==========

    event LendingPoolUpdated(address indexed oldPool, address indexed newPool);
    event YieldDeposited(uint256 amount);
    event YieldWithdrawn(uint256 amount);
    event YieldGenerated(uint256 amount);

    // ========== ERRORS ==========

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientIdleAssets();
    error InsufficientYieldAssets();

    // ========== CONSTRUCTOR ==========

    /**
     * @notice Constructor
     * @param asset_ The underlying asset (USDC, WETH, WBTC, USDT)
     * @param name_ Vault token name (e.g., "GTX USDC Vault")
     * @param symbol_ Vault token symbol (e.g., "gtxUSDC")
     * @param owner_ The owner address (ChainBalanceManager)
     * @param lendingPool_ The lending pool for yield generation
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address lendingPool_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(owner_) {
        if (owner_ == address(0)) revert ZeroAddress();

        lendingPool = lendingPool_; // Can be address(0) for testing
    }

    // ========== ERC4626 OVERRIDES ==========

    /**
     * @notice Get total assets in the vault (idle + yield protocol)
     * @dev Overrides ERC4626 to include assets in lending pool
     * @return Total assets including yield
     */
    function totalAssets() public view override returns (uint256) {
        uint256 idle = IERC20(asset()).balanceOf(address(this));

        // If no lending pool configured, only return idle assets
        if (lendingPool == address(0)) {
            return idle;
        }

        // Get actual balance in lending pool (includes yield)
        uint256 poolBalance = ILendingPool(lendingPool).balanceOf(asset(), address(this));

        return idle + poolBalance;
    }

    // ========== CUSTOM YIELD STRATEGY FUNCTIONS ==========

    /**
     * @notice Deposit idle funds into the yield-generating protocol
     * @dev Only callable by owner (ChainBalanceManager) for rebalancing
     * @param amount Amount to deposit into yield protocol
     */
    function depositToYieldProtocol(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (lendingPool == address(0)) revert ZeroAddress();

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle < amount) revert InsufficientIdleAssets();

        _depositToYieldProtocol(amount);

        emit YieldDeposited(amount);
    }

    /**
     * @notice Withdraw funds from the yield-generating protocol
     * @dev Only callable by owner (ChainBalanceManager) for rebalancing
     * @param amount Amount to withdraw from yield protocol
     */
    function withdrawFromYieldProtocol(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (lendingPool == address(0)) revert ZeroAddress();
        if (assetsInYield < amount) revert InsufficientYieldAssets();

        _withdrawFromYieldProtocol(amount);

        emit YieldWithdrawn(amount);
    }

    /**
     * @notice Update the lending pool address
     * @dev Only callable by owner to change yield strategy
     * @param newLendingPool The new lending pool address
     */
    function setLendingPool(address newLendingPool) external onlyOwner {
        address oldPool = lendingPool;
        lendingPool = newLendingPool;

        emit LendingPoolUpdated(oldPool, newLendingPool);
    }

    // ========== TESTING/SIMULATION FUNCTIONS ==========

    /**
     * @notice Simulate yield by allowing anyone to add assets
     * @dev In production, yield comes from lending protocols
     *      This function is for testing and simulation only
     * @param amount Amount of yield to add
     */
    function addYield(uint256 amount) external {
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
        // Yield automatically reflected in totalAssets() and share value
        emit YieldGenerated(amount);
    }

    // ========== VIEW FUNCTIONS ==========

    /**
     * @notice Get idle assets in the vault (not in yield protocol)
     * @return Idle assets
     */
    function idleAssets() external view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /**
     * @notice Get assets in the yield protocol
     * @return Assets in yield protocol (includes accrued yield)
     */
    function assetsInYieldProtocol() external view returns (uint256) {
        if (lendingPool == address(0)) {
            return 0;
        }
        return ILendingPool(lendingPool).balanceOf(asset(), address(this));
    }

    // ========== INTERNAL FUNCTIONS ==========

    /**
     * @notice Internal function to deposit to yield protocol
     * @param amount Amount to deposit
     */
    function _depositToYieldProtocol(uint256 amount) internal {
        // Approve lending pool to spend tokens
        IERC20(asset()).safeIncreaseAllowance(lendingPool, amount);

        // Deposit into lending pool
        ILendingPool(lendingPool).deposit(asset(), amount, address(this));

        assetsInYield += amount;
    }

    /**
     * @notice Internal function to withdraw from yield protocol
     * @param amount Amount to withdraw
     */
    function _withdrawFromYieldProtocol(uint256 amount) internal {
        // Get actual balance in lending pool (includes yield)
        uint256 poolBalance = ILendingPool(lendingPool).balanceOf(asset(), address(this));

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
        uint256 withdrawn = ILendingPool(lendingPool).withdraw(asset(), toWithdraw, address(this));

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
     * @notice Emergency withdraw function (owner only)
     * @dev Use only in case of emergency
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @param recipient The recipient address
     */
    function emergencyWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }
}
