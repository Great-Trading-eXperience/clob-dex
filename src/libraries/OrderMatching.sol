// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import "./OrderQueueLib.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./BokkyPooBahsRedBlackTreeLibrary.sol";

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
        uint48 timestamp,
        Price executionPrice,
        Quantity executedQuantity
    );

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

        while (currentOrderId != 0 && remainingAfter > 0) {
            IOrderBook.Order storage matchingOrder = queue.orders[
                currentOrderId
            ];
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

            uint128 matchingRemaining = uint128(
                Quantity.unwrap(matchingOrder.quantity)
            ) - uint128(Quantity.unwrap(matchingOrder.filled));
            uint128 executedQuantity = remainingAfter < matchingRemaining
                ? remainingAfter
                : matchingRemaining;

            matchingOrder.filled = Quantity.wrap(
                uint128(Quantity.unwrap(matchingOrder.filled)) +
                    executedQuantity
            );
            remainingAfter -= executedQuantity;
            filledAmount += executedQuantity;
            queue.totalVolume -= executedQuantity;

            if (
                uint128(Quantity.unwrap(matchingOrder.filled)) ==
                uint128(Quantity.unwrap(matchingOrder.quantity))
            ) {
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

            currentOrderId = nextOrderId;
        }

        return (remainingAfter, filledAmount);
    }
}
