// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "./OrderQueueLib.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./BokkyPooBahsRedBlackTreeLibrary.sol";
import {Status} from "../types/Types.sol";
import {IBalanceManager} from "../interfaces/IBalanceManager.sol";
import {Currency} from "../types/Currency.sol";
import {Quantity} from "../types/Types.sol";
import {PoolKey} from "../types/Pool.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {console} from "forge-std/Test.sol";

/// @title OrderMatching - A library
/// @notice Provides functionality to match orders in a Central Limit Order Book
/// @dev Implements price-time priority matching algorithm

library OrderMatching {
    using OrderQueueLib for OrderQueueLib.OrderQueue;
    using RBTree for RBTree.Tree;

    event OrderMatched(
        address indexed user,
        OrderId indexed buyOrderId,
        OrderId indexed sellOrderId,
        Side side,
        uint48 timestamp,
        Price executionPrice,
        Quantity executedQuantity
    );

    struct MatchOrder {
        address orderBook;
        IOrderBook.Order order;
        Side side;
        address trader;
        address balanceManager;
        PoolKey poolKey;
        address baseVault;
        address quoteVault;
    }

    event UpdateOrder(
        OrderId indexed orderId,
        uint48 timestamp,
        Quantity filled,
        Status status
    );

    /// @notice Matches an order against the opposite side of the order book
    /// @param _params The parameters for matching the order, including order details, pool, side, and trader
    /// @param orders The storage mapping containing all order queues
    /// @param priceTrees The price trees for order book organization
    /// @param isMarketOrder Whether the order is a market order
    /// @return filled The total quantity that was filled
    function matchOrder(
        MatchOrder memory _params,
        mapping(Side => mapping(Price => OrderQueueLib.OrderQueue))
            storage orders,
        mapping(Side => RBTree.Tree) storage priceTrees,
        bool isMarketOrder
    ) internal returns (uint128 filled) {
        IOrderBook.Order memory order = _params.order;
        Side side = _params.side;

        Side oppositeSide = side.opposite();
        uint128 remaining = uint128(Quantity.unwrap(order.quantity)) -
            uint128(Quantity.unwrap(order.filled));
        filled = 0;

        Price orderPrice = order.price;
        Price latestBestPrice = Price.wrap(0);
        uint128 previousRemaining = 0;

        while (remaining > 0) {
            Price bestPrice = getBestMatchingPrice(
                priceTrees[oppositeSide],
                orderPrice,
                side,
                isMarketOrder
            );

            if (
                Price.unwrap(bestPrice) == Price.unwrap(latestBestPrice) &&
                previousRemaining == remaining
            ) {
                bestPrice = side == Side.BUY
                    ? priceTrees[oppositeSide].next(bestPrice)
                    : priceTrees[oppositeSide].prev(bestPrice);
            }

            if (RBTree.isEmpty(bestPrice)) break;

            latestBestPrice = bestPrice;
            previousRemaining = remaining;

            (remaining, filled) = processMatchingAtPrice(
                _params,
                bestPrice,
                remaining,
                orders[oppositeSide][bestPrice],
                filled,
                isMarketOrder
            );

            if (orders[oppositeSide][bestPrice].orderCount == 0) {
                priceTrees[oppositeSide].remove(bestPrice);
            }
        }

        if (remaining == 0 && !isMarketOrder) {
            orders[side][order.price].removeOrder(OrderId.unwrap(order.id));

            if (orders[side][order.price].orderCount == 0) {
                priceTrees[side].remove(order.price);
            }
        }

        return filled;
    }

    function getBestMatchingPrice(
        RBTree.Tree storage priceTree,
        Price orderPrice,
        Side side,
        bool isMarketOrder
    ) private view returns (Price) {
        if (isMarketOrder) {
            return side == Side.BUY ? priceTree.first() : priceTree.last();
        }

        Price bestPrice = side == Side.BUY
            ? priceTree.first()
            : priceTree.last();
        if (RBTree.isEmpty(bestPrice)) return Price.wrap(0);

        bool priceIsValid = side == Side.BUY
            ? Price.unwrap(bestPrice) <= Price.unwrap(orderPrice)
            : Price.unwrap(bestPrice) >= Price.unwrap(orderPrice);

        return priceIsValid ? bestPrice : Price.wrap(0);
    }

    /// @notice Processes matches at a specific price level
    /// @param _params The parameters for matching, including order, side, pool, and trader
    /// @param matchPrice The price level to match at
    /// @param remaining The remaining quantity to be matched
    /// @param queue The order queue at the price level
    /// @return remainingAfter The remaining quantity after matching
    /// @return filledAmount The amount filled at this price level
    function processMatchingAtPrice(
        MatchOrder memory _params,
        Price matchPrice,
        uint128 remaining,
        OrderQueueLib.OrderQueue storage queue,
        uint128 totalFilled,
        bool isMarketOrder
    ) private returns (uint128 remainingAfter, uint128 filledAmount) {
        uint48 currentOrderId = queue.head;

        while (currentOrderId != 0 && remaining > 0) {
            (remaining, totalFilled, currentOrderId) = handleOrder(
                _params,
                matchPrice,
                remaining,
                queue,
                currentOrderId,
                totalFilled,
                isMarketOrder
            );
        }

        return (remaining, totalFilled);
    }

    function handleOrder(
        MatchOrder memory _params,
        Price matchPrice,
        uint128 remaining,
        OrderQueueLib.OrderQueue storage queue,
        uint48 currentOrderId,
        uint128 totalFilled,
        bool isMarketOrder
    )
        private
        returns (
            uint128 remainingAfter,
            uint128 newTotalFilled,
            uint48 nextOrderId
        )
    {
        return _handleOrderInternal(
            _params,
            matchPrice,
            remaining,
            queue,
            currentOrderId,
            totalFilled,
            isMarketOrder
        );
    }

    function _handleOrderInternal(
        MatchOrder memory _params,
        Price matchPrice,
        uint128 remaining,
        OrderQueueLib.OrderQueue storage queue,
        uint48 currentOrderId,
        uint128 totalFilled,
        bool isMarketOrder
    )
        private
        returns (
            uint128 remainingAfter,
            uint128 newTotalFilled,
            uint48 nextOrderId
        )
    {
        IOrderBook.Order storage matchingOrder = queue.orders[currentOrderId];
        nextOrderId = uint48(OrderId.unwrap(matchingOrder.next));

        if (matchingOrder.expiry <= block.timestamp) {
            queue.removeOrder(currentOrderId);
            return (remaining, totalFilled, nextOrderId);
        }

        if (matchingOrder.user == _params.trader) {
            return (remaining, totalFilled, nextOrderId);
        }

        uint128 matchingRemaining = uint128(
            Quantity.unwrap(matchingOrder.quantity)
        ) - uint128(Quantity.unwrap(matchingOrder.filled));
        uint128 executedQuantity = remaining < matchingRemaining
            ? remaining
            : matchingRemaining;

        uint128 convertedExcutedShare = (executedQuantity * 100) /
            matchingRemaining;

        if (_params.side == Side.BUY && _params.baseVault != address(0)) {
            uint256 shares = IBalanceManager(_params.balanceManager)
                .getLockedBalanceOfVault(
                    matchingOrder.user,
                    _params.orderBook,
                    _params.poolKey.baseCurrency,
                    _params.baseVault
                );
            matchingRemaining = uint128(
                ERC4626(_params.baseVault).convertToAssets(shares)
            );
            executedQuantity = remaining < matchingRemaining
                ? remaining
                : matchingRemaining;
            convertedExcutedShare = uint128(
                (shares * executedQuantity * 100) / matchingRemaining / 100
            );
            uint128(
                ERC4626(_params.baseVault).withdraw(
                    convertedExcutedShare,
                    _params.balanceManager,
                    _params.balanceManager
                )
            );
        } else if (
            _params.side == Side.SELL && _params.quoteVault != address(0)
        ) {
            uint256 shares = IBalanceManager(_params.balanceManager)
                .getLockedBalanceOfVault(
                    _params.trader,
                    _params.orderBook,
                    _params.poolKey.quoteCurrency,
                    _params.quoteVault
                );
            convertedExcutedShare = uint128(
                (shares * executedQuantity * 100) / matchingRemaining / 100
            );
            uint128(
                ERC4626(_params.quoteVault).withdraw(
                    convertedExcutedShare,
                    _params.balanceManager,
                    _params.balanceManager
                )
            );
        }

        matchingOrder.filled = Quantity.wrap(
            uint128(Quantity.unwrap(matchingOrder.filled)) +
                convertedExcutedShare
        );
        remaining -= executedQuantity;
        totalFilled += executedQuantity;
        queue.totalVolume -= convertedExcutedShare;

        transferBalances(
            _params.orderBook,
            _params.balanceManager,
            _params.trader,
            matchingOrder.user,
            _params.poolKey,
            _params.baseVault,
            _params.quoteVault,
            matchPrice,
            Quantity.wrap(executedQuantity),
            _params.side,
            isMarketOrder
        );

        if (
            uint128(Quantity.unwrap(matchingOrder.filled)) ==
            uint128(Quantity.unwrap(matchingOrder.quantity))
        ) {
            queue.removeOrder(currentOrderId);
        }

        emit OrderMatched(
            _params.trader,
            _params.side == Side.BUY
                ? _params.order.id
                : OrderId.wrap(currentOrderId),
            _params.side == Side.SELL
                ? _params.order.id
                : OrderId.wrap(currentOrderId),
            _params.side,
            uint48(block.timestamp),
            matchPrice,
            Quantity.wrap(executedQuantity)
        );

        return (remaining, totalFilled, nextOrderId);
    }

    function transferBalances(
        address orderBook,
        address balanceManager,
        address trader,
        address matchingUser,
        PoolKey memory poolKey,
        address baseVault,
        address quoteVault,
        Price matchPrice,
        Quantity executedQuantity,
        Side side,
        bool isMarketOrder
    ) private {
        (
            Currency currency0,
            uint256 amount0,
            Currency currency1,
            uint256 amount1
        ) = poolKey.calculateAmountsAndCurrencies(
                matchPrice,
                executedQuantity,
                side
            );

        if (!isMarketOrder) {
            IBalanceManager(balanceManager).unlock(
                trader,
                currency0,
                poolKey.quoteCurrency == currency0 ? quoteVault : baseVault,
                amount0
            );
        }

        console.log("AMOUNT0:", amount0);

        IBalanceManager(balanceManager).transferFrom(
            trader,
            matchingUser,
            currency0,
            amount0
        );

        IBalanceManager(balanceManager).transferLockedFrom(
            matchingUser,
            trader,
            currency1,
            amount1,
            poolKey.quoteCurrency == currency1 ? quoteVault : baseVault
        );
    }

    function processMatchingOrder(
        IOrderBook.Order memory order,
        Side side,
        Price matchPrice,
        uint128 remainingQty,
        OrderQueueLib.OrderQueue storage queue,
        address trader,
        uint48 currentOrderId
    ) private returns (uint48 nextOrderId, uint128 executedQuantity) {
        IOrderBook.Order storage matchingOrder = queue.orders[currentOrderId];
        nextOrderId = uint48(OrderId.unwrap(matchingOrder.next));
        executedQuantity = 0;

        if (matchingOrder.expiry <= block.timestamp) {
            queue.removeOrder(currentOrderId);
            emit UpdateOrder(
                OrderId.wrap(currentOrderId),
                uint48(block.timestamp),
                Quantity.wrap(0),
                Status.EXPIRED
            );
            return (nextOrderId, 0);
        }

        if (matchingOrder.user == trader) {
            return (nextOrderId, 0);
        }

        uint128 matchingRemaining = uint128(
            Quantity.unwrap(matchingOrder.quantity)
        ) - uint128(Quantity.unwrap(matchingOrder.filled));
        executedQuantity = remainingQty < matchingRemaining
            ? remainingQty
            : matchingRemaining;

        matchingOrder.filled = Quantity.wrap(
            uint128(Quantity.unwrap(matchingOrder.filled)) + executedQuantity
        );
        queue.totalVolume -= executedQuantity;

        emit OrderMatched(
            trader,
            side == Side.BUY ? order.id : OrderId.wrap(currentOrderId),
            side == Side.SELL ? order.id : OrderId.wrap(currentOrderId),
            side,
            uint48(block.timestamp),
            matchPrice,
            Quantity.wrap(executedQuantity)
        );

        if (
            uint128(Quantity.unwrap(matchingOrder.filled)) ==
            uint128(Quantity.unwrap(matchingOrder.quantity))
        ) {
            queue.removeOrder(currentOrderId);
        }

        return (nextOrderId, executedQuantity);
    }
}
