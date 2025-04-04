// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side} from "./types/Types.sol";
import {Currency} from "./types/Currency.sol";
import {PoolKey} from "./types/Pool.sol";
import {Price} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

/// @title GTXRouter - A router for interacting with the OrderBook
/// @notice Provides functions to place and cancel orders
contract GTXRouter {
    IPoolManager public poolManager;
    IBalanceManager public balanceManager;

    error SlippageTooHigh(uint256 received, uint256 minReceived);

    constructor(address _poolManager, address _balanceManager) {
        poolManager = IPoolManager(_poolManager);
        balanceManager = IBalanceManager(_balanceManager);
    }

    function placeOrder(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Price price,
        Quantity quantity,
        Side side,
        address user
    ) public returns (OrderId orderId) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderId = pool.orderBook.placeOrder(price, quantity, side, user);
    }

    function placeOrderWithDeposit(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Price price,
        Quantity quantity,
        Side side,
        address user
    ) external returns (OrderId orderId) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IBalanceManager(balanceManager).deposit(
            side == Side.BUY ? _quoteCurrency : _baseCurrency,
            Quantity.unwrap(quantity),
            msg.sender,
            user
        );
        orderId = placeOrder(
            _baseCurrency,
            _quoteCurrency,
            price,
            quantity,
            side,
            user
        );
    }

    function placeMarketOrder(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Quantity quantity,
        Side side,
        address user
    ) public returns (OrderId orderId) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        return _placeMarketOrder(key, quantity, side, user);
    }

    function _placeMarketOrder(
        PoolKey memory key,
        Quantity quantity,
        Side side,
        address user
    ) internal returns (OrderId orderId) {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderId = pool.orderBook.placeMarketOrder(quantity, side, user);
    }

    function placeMarketOrderWithDeposit(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Price price,
        Quantity quantity,
        Side side,
        address user
    ) external returns (OrderId orderId) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IBalanceManager(balanceManager).deposit(
            side == Side.BUY ? _quoteCurrency : _baseCurrency,
            Quantity.unwrap(quantity),
            msg.sender,
            user
        );
        return _placeMarketOrder(key, quantity, side, user);
    }

    function cancelOrder(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Side side,
        Price price,
        OrderId orderId
    ) external {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        pool.orderBook.cancelOrder(side, price, orderId, msg.sender);
    }

    function getBestPrice(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Side side
    ) external view returns (IOrderBook.PriceVolume memory) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getBestPrice(side);
    }

    function getOrderQueue(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Side side,
        Price price
    ) external view returns (uint48 orderCount, uint256 totalVolume) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getOrderQueue(side, price);
    }

    function getUserActiveOrders(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        address user
    ) external view returns (IOrderBook.Order[] memory) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getUserActiveOrders(user);
    }

    function getNextBestPrices(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        Side side,
        Price price,
        uint8 count
    ) external view returns (IOrderBook.PriceVolume[] memory) {
        PoolKey memory key = poolManager.createPoolKey(
            _baseCurrency,
            _quoteCurrency
        );
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getNextBestPrices(side, price, count);
    }

    /**
     * @notice Swaps one token for another with automatic routing
     * @param srcCurrency The currency the user is providing
     * @param dstCurrency The currency the user wants to receive
     * @param srcAmount The amount of source currency to swap
     * @param minDstAmount The minimum amount of destination currency to receive
     * @param maxHops Maximum number of intermediate hops allowed (1-3)
     * @param user The user address that will receive the destination currency
     * @return receivedAmount The actual amount of destination currency received
     */
    function swap(
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        uint8 maxHops,
        address user
    ) external returns (uint256 receivedAmount) {
        require(
            Currency.unwrap(srcCurrency) != Currency.unwrap(dstCurrency),
            "Same currency"
        );
        require(maxHops <= 3, "Too many hops");

        // Try direct swap first (most efficient)
        if (poolManager.poolExists(srcCurrency, dstCurrency)) {
            receivedAmount = executeDirectSwap(
                srcCurrency,
                dstCurrency,
                srcCurrency,
                dstCurrency,
                srcAmount,
                minDstAmount,
                user
            );
        } else if (poolManager.poolExists(dstCurrency, srcCurrency)) {
            receivedAmount = executeDirectSwap(
                dstCurrency,
                srcCurrency,
                srcCurrency,
                dstCurrency,
                srcAmount,
                minDstAmount,
                user
            );
        }

        // If no direct pool, try to find intermediaries
        // Try common intermediaries first (from PoolManager)
        Currency[] memory intermediaries = poolManager
            .getCommonIntermediaries();

        // Try one-hop paths through intermediaries
        if (receivedAmount == 0) {
            for (uint i = 0; i < intermediaries.length; i++) {
                Currency intermediary = intermediaries[i];

                // Skip if intermediary is source or destination currency
                if (
                    Currency.unwrap(intermediary) ==
                    Currency.unwrap(srcCurrency) ||
                    Currency.unwrap(intermediary) ==
                    Currency.unwrap(dstCurrency)
                ) {
                    continue;
                }

                // Check if both pools exist
                if (
                    (poolManager.poolExists(srcCurrency, intermediary) &&
                        poolManager.poolExists(intermediary, dstCurrency)) ||
                    (poolManager.poolExists(srcCurrency, intermediary) &&
                        poolManager.poolExists(dstCurrency, intermediary)) ||
                    (poolManager.poolExists(intermediary, srcCurrency) &&
                        poolManager.poolExists(dstCurrency, intermediary)) ||
                    (poolManager.poolExists(intermediary, srcCurrency) &&
                        poolManager.poolExists(dstCurrency, intermediary))
                ) {
                    // Execute multi-hop swap where second pool is accessed in reverse
                    receivedAmount = executeMultiHopSwap(
                        srcCurrency,
                        intermediary,
                        dstCurrency,
                        srcAmount,
                        minDstAmount,
                        user
                    );
                }
            }
        }

        if (receivedAmount > 0) {
            balanceManager.transferOut(user, user, dstCurrency, receivedAmount);
            return receivedAmount;
        }

        revert("No valid swap path found");
    }

    /**
     * @notice Execute a direct swap between two currencies
     */
    function executeDirectSwap(
        Currency baseCurrency,
        Currency quoteCurrency,
        Currency srcCurrency,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal returns (uint256 receivedAmount) {
        // Determine the pool key and side
        PoolKey memory key = poolManager.createPoolKey(
            baseCurrency,
            quoteCurrency
        );
        Side side;

        // Determine side based on whether source is base or quote
        if (Currency.unwrap(srcCurrency) == Currency.unwrap(baseCurrency)) {
            side = Side.SELL; // Selling base currency for quote currency
        } else {
            side = Side.BUY; // Buying base currency with quote currency
        }

        IPoolManager.Pool memory pool = poolManager.getPool(key);

        // Calculate the quantity
        Quantity quantity;

        if (side == Side.SELL) {
            quantity = Quantity.wrap(uint128(srcAmount));
            if (srcAmount == 0) {
                revert("Amount too small");
            }
        } else {
            // When buying base, we need to estimate the quantity
            IOrderBook.PriceVolume memory bestPrice = pool
                .orderBook
                .getBestPrice(Side.SELL);
            if (Price.unwrap(bestPrice.price) == 0) {
                revert("No liquidity available");
            }

            quantity = Quantity.wrap(uint128(srcAmount));
            if (Quantity.unwrap(quantity) == uint128(0)) {
                revert("Amount too small");
            }
        }

        // Deposit the source currency to the protocol
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);

        // Record balance before swap to calculate actual received amount
        uint256 balanceBefore = balanceManager.getBalance(user, dstCurrency);

        // Execute the market order
        OrderId orderId = _placeMarketOrder(key, quantity, side, user);

        // Calculate the amount received
        uint256 balanceAfter = balanceManager.getBalance(user, dstCurrency);

        receivedAmount = balanceAfter - balanceBefore;

        // Ensure minimum destination amount is met
        if (receivedAmount < minDstAmount) {
            revert SlippageTooHigh(receivedAmount, minDstAmount);
        }

        return receivedAmount;
    }

    /**
     * @notice Execute a multi-hop swap through one intermediary
     */
    function executeMultiHopSwap(
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal returns (uint256 receivedAmount) {
        // Deposit the source currency to the protocol
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);

        uint256 intermediateAmount;

        if (poolManager.poolExists(srcCurrency, intermediary)) {
            intermediateAmount = executeSwapStep(
                srcCurrency,
                intermediary,
                srcCurrency,
                intermediary,
                srcAmount,
                0,
                user,
                Side.SELL
            );
        } else {
            intermediateAmount = executeSwapStep(
                srcCurrency,
                intermediary,
                intermediary,
                srcCurrency,
                srcAmount,
                0,
                user,
                Side.BUY
            );
        }

        // If we received 0 from the first swap, something went wrong
        if (intermediateAmount == 0) {
            revert("First hop failed");
        }

        // Execute second swap (intermediary -> dstCurrency)
        // For the final swap, use the provided minDstAmount
       if (poolManager.poolExists(dstCurrency, intermediary)) {
            return executeSwapStep(
                intermediary,
                dstCurrency,
                dstCurrency,
                intermediary,
                intermediateAmount,
                minDstAmount,
                user,
                Side.BUY
            );
        } else {
            return executeSwapStep(
                intermediary,
                dstCurrency,
                intermediary,
                dstCurrency,
                intermediateAmount,
                0,
                user,
                Side.SELL
            );
        }
    }

    /**
     * @notice Execute a single swap step within a multi-hop swap
     */
    function executeSwapStep(
        Currency srcCurrency,
        Currency dstCurrency,
        Currency baseCurrency,
        Currency quoteCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user,
        Side side
    ) internal returns (uint256 receivedAmount) {
        // Calculate the quantity
        Quantity quantity;

        quantity = Quantity.wrap(uint128(srcAmount));
        if (srcAmount == 0) {
            revert("Amount too small for swap step");
        }

        // Determine the pool key and side
        PoolKey memory key = poolManager.createPoolKey(
            baseCurrency,
            quoteCurrency
        );

        // Record balance before swap to calculate actual received amount
        uint256 balanceBefore = balanceManager.getBalance(user, dstCurrency);

        // Execute the market order
        OrderId orderId = _placeMarketOrder(key, quantity, side, user);

        // Calculate the amount received
        uint256 balanceAfter = balanceManager.getBalance(user, dstCurrency);
        receivedAmount = balanceAfter - balanceBefore;

        // Ensure minimum destination amount is met (if specified)
        if (minDstAmount > 0 && receivedAmount < minDstAmount) {
            revert SlippageTooHigh(receivedAmount, minDstAmount);
        }

        return receivedAmount;
    }

    /**
     * @notice Execute a multi-hop swap where the second pool is accessed in reverse
     * @dev Used when we have pools: srcCurrency-intermediary and dstCurrency-intermediary
     */
    function executeReverseMultiHopSwap(
        Currency srcCurrency,
        Currency intermediary,
        Currency dstCurrency,
        uint256 srcAmount,
        uint256 minDstAmount,
        address user
    ) internal returns (uint256 receivedAmount) {
        // Deposit the source currency to the protocol
        balanceManager.deposit(srcCurrency, srcAmount, msg.sender, user);

        // Execute first swap (srcCurrency -> intermediary)
        uint256 intermediateAmount = executeSwapStep(
            srcCurrency,
            intermediary,
            dstCurrency,
            srcCurrency,
            srcAmount,
            0, // No minimum for intermediate step
            user,
            Side.SELL
        );

        // If we received 0 from the first swap, something went wrong
        if (intermediateAmount == 0) {
            revert("First hop failed");
        }

        // Execute second swap (intermediary -> dstCurrency)
        // Note: For the second step, we're selling the intermediary to get dstCurrency
        // We need to use the pool dstCurrency-intermediary but in reverse
        PoolKey memory reverseKey = poolManager.createPoolKey(
            dstCurrency,
            intermediary
        );

        // Record balance before swap
        uint256 balanceBefore = balanceManager.getBalance(user, dstCurrency);

        // Calculate quantity for the reverse swap
        IPoolManager.Pool memory pool = poolManager.getPool(reverseKey);
        IOrderBook.PriceVolume memory bestPrice = pool.orderBook.getBestPrice(
            Side.BUY
        );
        if (Price.unwrap(bestPrice.price) == 0) {
            revert("No liquidity available for reverse swap");
        }

        Quantity quantity = Quantity.wrap(
            uint128(intermediateAmount / (Price.unwrap(bestPrice.price) / 1e18))
        );

        if (Quantity.unwrap(quantity) == uint128(0)) {
            revert("Amount too small for reverse swap");
        }

        // Execute the market order (buying dstCurrency with intermediary)
        OrderId orderId = _placeMarketOrder(
            reverseKey,
            quantity,
            Side.BUY,
            user
        );

        // Calculate received amount
        uint256 balanceAfter = balanceManager.getBalance(user, dstCurrency);
        receivedAmount = balanceAfter - balanceBefore;

        // Check minimum received amount
        if (receivedAmount < minDstAmount) {
            revert SlippageTooHigh(receivedAmount, minDstAmount);
        }

        return receivedAmount;
    }
}
