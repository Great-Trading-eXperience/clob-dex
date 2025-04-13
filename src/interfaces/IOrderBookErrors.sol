// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * @title IOrderBookErrors
 * @notice Interface defining all custom errors used by the OrderBook system
 */
interface IOrderBookErrors {
    error SlippageTooHigh(uint256 received, uint256 minReceived);
    error FillOrKillNotFulfilled(uint128 filledAmount, uint128 requestedAmount);
    error InvalidOrderType();
    error InvalidPrice(uint256 price);
    error InvalidPriceIncrement();
    error InvalidQuantity();
    error InvalidQuantityIncrement();
    error OrderHasNoLiquidity();
    error OrderTooLarge(uint256 amount, uint256 maxAmount);
    error OrderTooSmall(uint256 amount, uint256 minAmount);
    error PostOnlyWouldTake();
    error SlippageExceeded(uint256 requestedPrice, uint256 limitPrice);
    error TradingPaused();
    error UnauthorizedCancellation();
    error UnauthorizedRouter(address reouter);
    error OrderNotFound();
    error InsufficientBalance(uint256 requiredDeposit, uint256 userBalance);
}
