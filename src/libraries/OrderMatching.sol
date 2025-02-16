// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import "./OrderQueueLib.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./BokkyPooBahsRedBlackTreeLibrary.sol";
import {Status} from "../types/Types.sol";

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

    event UpdateOrder(OrderId indexed orderId, uint48 timestamp, Quantity filled, Status status);

    /// @notice Matches an order against the opposite side of the order book
    /// @param order The order to be matched
    /// @param orderSide The side of the order (BUY/SELL)
    /// @param orders The storage mapping containing all order queues
    /// @param priceTrees The price trees for order book organization
    /// @param trader The address of the trader placing the order
    /// @param isMarketOrder Whether the order is a market order
    /// @return filled The total quantity that was filled
    function matchOrder(
        IOrderBook.Order memory order,
        Side orderSide,
        mapping(Side => mapping(Price => OrderQueueLib.OrderQueue))
            storage orders,
        mapping(Side => RBTree.Tree) storage priceTrees,
        address trader,
        bool isMarketOrder
    ) internal returns (uint128 filled) {
        Side oppositeSide = orderSide == Side.BUY ? Side.SELL : Side.BUY;
        uint128 remaining = uint128(Quantity.unwrap(order.quantity)) -
            uint128(Quantity.unwrap(order.filled));
        filled = 0;

        while (remaining > 0) {
            Price bestPrice = getBestMatchingPrice(
                priceTrees[oppositeSide],
                order.price,
                orderSide,
                isMarketOrder
            );

            if (RBTree.isEmpty(bestPrice)) break;

            uint128 newFilled;
            (remaining, newFilled) = processMatchingAtPrice(
                order,
                orderSide,
                bestPrice,
                remaining,
                orders[oppositeSide][bestPrice],
                trader
            );
            filled += newFilled;
            order.filled = Quantity.wrap(
                uint128(Quantity.unwrap(order.filled)) + newFilled
            );

            if (orders[oppositeSide][bestPrice].orderCount == 0) {
                priceTrees[oppositeSide].remove(bestPrice);
            }
        }

        if (remaining == 0 && !isMarketOrder) {
            orders[orderSide][order.price].removeOrder(
                OrderId.unwrap(order.id)
            );

            if (orders[orderSide][order.price].orderCount == 0) {
                priceTrees[orderSide].remove(order.price);
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
    /// @param order The order being matched
    /// @param side The side of the order
    /// @param matchPrice The price level to match at
    /// @param remaining The remaining quantity to be matched
    /// @param queue The order queue at the price level
    /// @param trader The address of the trader
    /// @return remainingAfter The remaining quantity after matching
    /// @return filledAmount The amount filled at this price level
    function processMatchingAtPrice(
        IOrderBook.Order memory order,
        Side side,
        Price matchPrice,
        uint128 remaining,
        OrderQueueLib.OrderQueue storage queue,
        address trader
    ) private returns (uint128 remainingAfter, uint128 filledAmount) {
        uint48 currentOrderId = queue.head;
        filledAmount = 0;
        remainingAfter = remaining;
        uint128 executedQuantity;

        while (currentOrderId != 0 && remainingAfter > 0) {
            (currentOrderId, executedQuantity) = processMatchingOrder(
                order,
                side,
                matchPrice,
                remainingAfter,
                queue,
                trader,
                currentOrderId
            );

            remainingAfter -= executedQuantity;
            filledAmount += executedQuantity;

            if (filledAmount > 0) {
                emit UpdateOrder(order.id, uint48(block.timestamp), Quantity.wrap(filledAmount), remainingAfter == 0 ? Status.FILLED : Status.PARTIALLY_FILLED);
            }
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
