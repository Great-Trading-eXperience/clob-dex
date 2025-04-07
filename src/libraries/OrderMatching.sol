// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import "./OrderQueueLib.sol";
import {
    BokkyPooBahsRedBlackTreeLibrary as RBTree, Price
} from "./BokkyPooBahsRedBlackTreeLibrary.sol";
import {Status} from "../types/Types.sol";
import {IBalanceManager} from "../interfaces/IBalanceManager.sol";
import {Currency} from "../types/Currency.sol";
import {Quantity, OrderType} from "../types/Types.sol";
import {PoolKey, PoolIdLibrary} from "../types/Pool.sol";
import {console} from "forge-std/Test.sol";

/// @title OrderMatching - A library for matching orders in a CLOB
/// @notice Provides functionality to match orders in a Central Limit Order Book
/// @dev Implements price-time priority matching algorithm

library OrderMatching {
    using OrderQueueLib for OrderQueueLib.OrderQueue;
    using RBTree for RBTree.Tree;
    using PoolIdLibrary for PoolKey;

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
        IOrderBook orderBook;
    }

    event UpdateOrder(OrderId indexed orderId, uint48 timestamp, Quantity filled, Status status);

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

        uint128 remaining =
            uint128(Quantity.unwrap(order.quantity)) - uint128(Quantity.unwrap(order.filled));

        filled = 0;

        Price orderPrice = order.price;
        Price latestBestPrice = Price.wrap(0);
        uint128 previousRemaining = 0;

        while (remaining > 0) {
            Price bestPrice =
                getBestMatchingPrice(priceTrees[oppositeSide], orderPrice, side, isMarketOrder);

            if (
                Price.unwrap(bestPrice) == Price.unwrap(latestBestPrice)
                    && previousRemaining == remaining
            ) {
                bestPrice = side == Side.BUY
                    ? priceTrees[oppositeSide].next(bestPrice)
                    : priceTrees[oppositeSide].prev(bestPrice);
            }

            if (RBTree.isEmpty(bestPrice)) break;

            latestBestPrice = bestPrice;
            previousRemaining = remaining;
            uint48 currentOrderId = orders[oppositeSide][bestPrice].head;

            while (currentOrderId != 0 && remaining > 0) {
                (remaining, filled, currentOrderId) = handleOrder(
                    _params,
                    bestPrice,
                    remaining,
                    orders[oppositeSide][bestPrice],
                    currentOrderId,
                    filled,
                    isMarketOrder
                );
            }

            if (
                orders[oppositeSide][bestPrice].orderCount == 0
                    && priceTrees[oppositeSide].exists(bestPrice)
            ) {
                priceTrees[oppositeSide].remove(bestPrice);
            }
        }

        if (remaining == 0 && !isMarketOrder) {
            orders[side][order.price].removeOrder(OrderId.unwrap(order.id));

            if (orders[side][order.price].orderCount == 0 && priceTrees[side].exists(order.price)) {
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

        Price bestPrice = side == Side.BUY ? priceTree.first() : priceTree.last();
        if (RBTree.isEmpty(bestPrice)) return Price.wrap(0);

        bool priceIsValid = side == Side.BUY
            ? Price.unwrap(bestPrice) <= Price.unwrap(orderPrice)
            : Price.unwrap(bestPrice) >= Price.unwrap(orderPrice);

        return priceIsValid ? bestPrice : Price.wrap(0);
    }

    function handleOrder(
        MatchOrder memory _params,
        Price matchPrice,
        uint128 remaining,
        OrderQueueLib.OrderQueue storage queue,
        uint48 currentOrderId,
        uint128 totalFilled,
        bool isMarketOrder
    ) private returns (uint128 remainingAfter, uint128 newTotalFilled, uint48 nextOrderId) {
        IOrderBook.Order storage matchingOrder = queue.orders[currentOrderId];
        nextOrderId = uint48(OrderId.unwrap(matchingOrder.next));

        if (matchingOrder.expiry <= block.timestamp) {
            queue.removeOrder(currentOrderId);
            emit UpdateOrder(
                OrderId.wrap(currentOrderId),
                uint48(block.timestamp),
                Quantity.wrap(0),
                Status.EXPIRED
            );
            return (remaining, totalFilled, nextOrderId);
        }

        if (matchingOrder.user == _params.trader) {
            if (address(_params.orderBook) != address(0)) {
                Side oppositeSide = _params.side.opposite();
                _params.orderBook.cancelOrder(
                    oppositeSide, matchPrice, OrderId.wrap(currentOrderId), matchingOrder.user
                );
            }

            return (remaining, totalFilled, nextOrderId);
        }

        uint128 matchingOrderOriginalQuantity = uint128(Quantity.unwrap(matchingOrder.quantity));
        uint128 matchingOrderOriginalFilled = uint128(Quantity.unwrap(matchingOrder.filled));
        uint128 matchingRemaining = matchingOrderOriginalQuantity - matchingOrderOriginalFilled;
        uint128 executedQuantity = remaining < matchingRemaining ? remaining : matchingRemaining;

        remaining -= executedQuantity;
        totalFilled += executedQuantity;

        matchingOrder.filled = Quantity.wrap(matchingOrderOriginalFilled + executedQuantity);
        queue.totalVolume -= executedQuantity;

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

        if (matchingOrderOriginalFilled + executedQuantity == matchingOrderOriginalQuantity) {
            queue.removeOrder(currentOrderId);
        }

        emit OrderMatched(
            _params.trader,
            _params.side == Side.BUY ? _params.order.id : OrderId.wrap(currentOrderId),
            _params.side == Side.SELL ? _params.order.id : OrderId.wrap(currentOrderId),
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
        uint256 baseAmount = Quantity.unwrap(executedQuantity);

        uint256 quoteAmount = PoolIdLibrary.baseToQuote(
            baseAmount, Price.unwrap(matchPrice), poolKey.baseCurrency.decimals()
        );

        if (side == Side.SELL) {
            if (!isMarketOrder) {
                IBalanceManager(balanceManager).unlock(trader, poolKey.baseCurrency, baseAmount);
            }

            IBalanceManager(balanceManager).transferFrom(
                trader, matchingUser, poolKey.baseCurrency, baseAmount
            );

            IBalanceManager(balanceManager).transferLockedFrom(
                matchingUser, trader, poolKey.quoteCurrency, quoteAmount
            );
        } else {
            if (!isMarketOrder) {
                IBalanceManager(balanceManager).unlock(trader, poolKey.quoteCurrency, quoteAmount);
            }
            IBalanceManager(balanceManager).transferFrom(
                trader, matchingUser, poolKey.quoteCurrency, quoteAmount
            );
            IBalanceManager(balanceManager).transferLockedFrom(
                matchingUser, trader, poolKey.baseCurrency, baseAmount
            );
        }
    }
}
