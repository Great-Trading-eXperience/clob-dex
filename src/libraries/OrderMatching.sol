// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import "./OrderQueueLib.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./BokkyPooBahsRedBlackTreeLibrary.sol";
import {Status} from "../types/Types.sol";
import {IERC6909Lock} from "../interfaces/external/IERC6909Lock.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../types/Currency.sol";
import {Quantity} from "../types/Types.sol";

/// @title OrderMatching - A library for matching orders in a CLOB
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
        IOrderBook.Order order;
        IOrderBook.Pool pool;
        Side side;
        address trader;
    }

    /// @notice Matches an order against the opposite side of the order book
    /// @param _params The parameters for matching the order, including order details, pool, side, and trader
    /// @param orders The storage mapping containing all order queues
    /// @param priceTrees The price trees for order book organization
    /// @param isMarketOrder Whether the order is a market order
    /// @return filled The total quantity that was filled
    function matchOrder(
        MatchOrder memory _params,
        mapping(Side => mapping(Price => OrderQueueLib.OrderQueue)) storage orders,
        mapping(Side => RBTree.Tree) storage priceTrees,
        bool isMarketOrder
    ) internal returns (uint128 filled) {
        IOrderBook.Order memory order = _params.order;
        Side side = _params.side;

        Side oppositeSide = side.opposite();
        uint128 remaining = uint128(Quantity.unwrap(order.quantity)) - uint128(Quantity.unwrap(order.filled));
        filled = 0;

        while (remaining > 0) {
            Price bestPrice = getBestMatchingPrice(priceTrees[oppositeSide], order.price, side, isMarketOrder);

            if (RBTree.isEmpty(bestPrice)) break;
            uint128 newFilled;

            (remaining, newFilled) =
                processMatchingAtPrice(_params, bestPrice, remaining, orders[oppositeSide][bestPrice]);
            filled += newFilled;
            order.filled = Quantity.wrap(uint128(Quantity.unwrap(order.filled)) + newFilled);

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

    /// @notice Gets the best matching price for an order
    /// @param priceTree The price tree to search in
    /// @param orderPrice The price of the order
    /// @param side The side of the order
    /// @param isMarketOrder Whether the order is a market order
    /// @return The best matching price
    function getBestMatchingPrice(RBTree.Tree storage priceTree, Price orderPrice, Side side, bool isMarketOrder)
        private
        view
        returns (Price)
    {
        if (isMarketOrder) {
            return side == Side.BUY ? priceTree.first() : priceTree.last();
        }

        Price bestPrice = side == Side.BUY ? priceTree.first() : priceTree.last();
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
        OrderQueueLib.OrderQueue storage queue
    ) private returns (uint128 remainingAfter, uint128 filledAmount) {
        IOrderBook.Order memory order = _params.order;
        IOrderBook.Pool memory pool = _params.pool;
        Side side = _params.side;
        address trader = _params.trader;
        uint48 currentOrderId = queue.head;

        filledAmount = 0;
        remainingAfter = remaining;
        uint128 executedQuantity;

        while (currentOrderId != 0 && remainingAfter > 0) {
            IOrderBook.Order storage matchingOrder = queue.orders[currentOrderId];
            uint48 nextOrderId = uint48(OrderId.unwrap(matchingOrder.next));

            if (matchingOrder.expiry <= block.timestamp) {
                queue.removeOrder(currentOrderId);
                currentOrderId = nextOrderId;
                continue;
            }

            if (matchingOrder.user == trader) {
                currentOrderId = nextOrderId;
                continue;
            }
            uint128 matchingRemaining =
                uint128(Quantity.unwrap(matchingOrder.quantity)) - uint128(Quantity.unwrap(matchingOrder.filled));
            executedQuantity = remainingAfter < matchingRemaining ? remainingAfter : matchingRemaining;

            matchingOrder.filled = Quantity.wrap(uint128(Quantity.unwrap(matchingOrder.filled)) + executedQuantity);
            remainingAfter -= executedQuantity;
            filledAmount += executedQuantity;

            if (uint128(Quantity.unwrap(matchingOrder.filled)) == uint128(Quantity.unwrap(matchingOrder.quantity))) {
                queue.removeOrder(currentOrderId);
            }

            emit OrderMatched(
                trader,
                side == Side.BUY ? order.id : OrderId.wrap(currentOrderId),
                side == Side.SELL ? order.id : OrderId.wrap(currentOrderId),
                uint48(block.timestamp),
                matchPrice,
                Quantity.wrap(executedQuantity)
            );

            // Transfer Locked balance
            (Currency currency0, uint256 amount0) = IPoolManager(pool.poolManager).calculateAmountAndCurrency(
                pool.poolKey, matchPrice, Quantity.wrap(executedQuantity), side
            );
            IERC6909Lock(pool.poolManager).transferLockedFrom(trader, matchingOrder.user, currency0.toId(), amount0);

            (Currency currency1, uint256 amount1) = IPoolManager(pool.poolManager).calculateAmountAndCurrency(
                pool.poolKey, matchPrice, Quantity.wrap(executedQuantity), side.opposite()
            );
            IERC6909Lock(pool.poolManager).transferLockedFrom(matchingOrder.user, trader, currency1.toId(), amount1);

            currentOrderId = nextOrderId;
        }

        return (remainingAfter, filledAmount);
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
            emit UpdateOrder(OrderId.wrap(currentOrderId), uint48(block.timestamp), Quantity.wrap(0), Status.EXPIRED);
            return (nextOrderId, 0);
        }

        if (matchingOrder.user == trader) {
            return (nextOrderId, 0);
        }

        uint128 matchingRemaining =
            uint128(Quantity.unwrap(matchingOrder.quantity)) - uint128(Quantity.unwrap(matchingOrder.filled));
        executedQuantity = remainingQty < matchingRemaining ? remainingQty : matchingRemaining;

        matchingOrder.filled = Quantity.wrap(uint128(Quantity.unwrap(matchingOrder.filled)) + executedQuantity);
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

        if (uint128(Quantity.unwrap(matchingOrder.filled)) == uint128(Quantity.unwrap(matchingOrder.quantity))) {
            queue.removeOrder(currentOrderId);
        }

        return (nextOrderId, executedQuantity);
    }
}
