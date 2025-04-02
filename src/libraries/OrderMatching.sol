// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "./OrderQueueLib.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./BokkyPooBahsRedBlackTreeLibrary.sol";
import {Status} from "../types/Types.sol";
import {IBalanceManager} from "../interfaces/IBalanceManager.sol";
import {Currency} from "../types/Currency.sol";
import {Quantity} from "../types/Types.sol";
import {PoolKey} from "../types/Pool.sol";

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
        Side side;
        address trader;
        address balanceManager;
        PoolKey poolKey;
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

            if (!RBTree.isEmpty(bestPrice)) {
                latestBestPrice = bestPrice;
                previousRemaining = remaining;

                uint128 convertedRemaining = remaining;
                uint128 convertedFilled = filled;

                if (side == Side.BUY) {
                    convertedRemaining = uint128(
                        _params.poolKey.convertCurrency(
                            bestPrice,
                            Quantity.wrap(remaining),
                            false
                        )
                    );
                    convertedFilled = uint128(
                        _params.poolKey.convertCurrency(
                            bestPrice,
                            Quantity.wrap(filled),
                            false
                        )
                    );
                }

                (remaining, filled) = processMatchingAtPrice(
                    _params,
                    bestPrice,
                    convertedRemaining,
                    orders[oppositeSide][bestPrice],
                    convertedFilled,
                    isMarketOrder
                );

                if (orders[oppositeSide][bestPrice].orderCount == 0) {
                    priceTrees[oppositeSide].remove(bestPrice);
                }
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

        if (_params.side == Side.BUY) {
            remainingAfter = _params.poolKey.convertCurrency(
                matchPrice,
                Quantity.wrap(remaining),
                true
            );
            filledAmount = _params.poolKey.convertCurrency(
                matchPrice,
                Quantity.wrap(totalFilled),
                true
            );
        } else {
            remainingAfter = _params.poolKey.convertCurrency(
                matchPrice,
                Quantity.wrap(remaining),
                false
            );
            
            filledAmount = _params.poolKey.convertCurrency(
                matchPrice,
                Quantity.wrap(totalFilled),
                false
            );
        }

        return (remainingAfter, filledAmount);
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

        uint128 convertedMatchingRemaining = matchingRemaining;
        if (_params.side == Side.SELL) {
            convertedMatchingRemaining = uint128(
                _params.poolKey.convertCurrency(
                    matchPrice,
                    Quantity.wrap(matchingRemaining),
                    false
                )
            );
        }

        uint128 executedQuantity = remaining < convertedMatchingRemaining
            ? remaining
            : convertedMatchingRemaining;

        remaining -= executedQuantity;
        totalFilled += executedQuantity;

        if (_params.side == Side.SELL) {
            uint128 convertedExecutedQuantity = uint128(
                _params.poolKey.convertCurrency(
                    matchPrice,
                    Quantity.wrap(executedQuantity),
                    true
                )
            );
            matchingOrder.filled = Quantity.wrap(
                uint128(Quantity.unwrap(matchingOrder.filled)) +
                    convertedExecutedQuantity
            );
            queue.totalVolume -= convertedExecutedQuantity;
        }

        transferBalances(
            _params.balanceManager,
            _params.trader,
            matchingOrder.user,
            _params.poolKey,
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
        address balanceManager,
        address trader,
        address matchingUser,
        PoolKey memory poolKey,
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
            IBalanceManager(balanceManager).unlock(trader, currency0, amount0);
        }

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
            amount1
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
