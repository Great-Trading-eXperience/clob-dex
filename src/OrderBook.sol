// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side} from "./types/Types.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderQueueLib} from "./libraries/OrderQueue.sol";
import {OrderMatchingLib} from "./libraries/OrderMatching.sol";
import {OrderPacking} from "./libraries/OrderPacking.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title OrderBook - A Central Limit Order Book implementation
/// @notice Manages limit and market orders in a decentralized exchange
/// @dev Implements price-time priority matching with reentrance protection
contract OrderBook is IOrderBook, ReentrancyGuard {
    using RBTree for RBTree.Tree;
    using OrderQueueLib for OrderQueueLib.OrderQueue;
    using OrderMatchingLib for *;
    using EnumerableSet for EnumerableSet.UintSet;
    using OrderPacking for *;

    error UnauthorizedCancellation();
    error InvalidPrice(uint256 price);
    error InvalidQuantity();

    mapping(address => EnumerableSet.UintSet) private activeUserOrders;
    mapping(Side => RBTree.Tree) private priceTrees;
    mapping(Side => mapping(Price => OrderQueueLib.OrderQueue))
        private orderQueues;

    uint48 private nextOrderId = 1;

    /// @notice Places a new limit order
    /// @param price The price of the order
    /// @param quantity The quantity of the order
    /// @param side The side of the order (BUY/SELL)
    /// @return orderId The ID of the placed order
    function placeOrder(
        Price price,
        Quantity quantity,
        Side side
    ) external override nonReentrant returns (OrderId) {
        if (Quantity.unwrap(quantity) == 0) revert InvalidQuantity();
        if (Price.unwrap(price) == 0) revert InvalidPrice(Price.unwrap(price));

        OrderId orderId = OrderId.wrap(nextOrderId++);

        Order memory newOrder = Order({
            id: orderId,
            user: msg.sender,
            next: OrderId.wrap(0),
            prev: OrderId.wrap(0),
            price: price,
            timestamp: uint48(block.timestamp),
            quantity: quantity,
            filled: Quantity.wrap(0)
        });

        // Add order to queue
        orderQueues[side][price].addOrder(newOrder, false);

        // Update price tree
        if (!priceTrees[side].exists(price)) {
            priceTrees[side].insert(price);
        }

        // Track user's order
        activeUserOrders[msg.sender].add(
            OrderPacking.packOrder(side, price, OrderId.unwrap(orderId))
        );

        emit OrderPlaced(
            orderId,
            msg.sender,
            side,
            price,
            quantity,
            uint48(block.timestamp),
            false
        );

        // Match order
        OrderMatchingLib.matchOrder(
            newOrder,
            side,
            orderQueues,
            priceTrees,
            msg.sender,
            false
        );

        return orderId;
    }

    /// @notice Places a new market order
    /// @param quantity The quantity of the order
    /// @param side The side of the order (BUY/SELL)
    /// @return orderId The ID of the placed order
    function placeMarketOrder(
        Quantity quantity,
        Side side
    ) external override nonReentrant returns (OrderId) {
        if (Quantity.unwrap(quantity) == 0) revert InvalidQuantity();

        OrderId orderId = OrderId.wrap(nextOrderId++);

        Order memory marketOrder = Order({
            id: orderId,
            user: msg.sender,
            next: OrderId.wrap(0),
            prev: OrderId.wrap(0),
            price: Price.wrap(0),
            timestamp: uint48(block.timestamp),
            quantity: quantity,
            filled: Quantity.wrap(0)
        });

        OrderMatchingLib.matchOrder(
            marketOrder,
            side,
            orderQueues,
            priceTrees,
            msg.sender,
            true
        );

        emit OrderPlaced(
            orderId,
            msg.sender,
            side,
            Price.wrap(0),
            quantity,
            uint48(block.timestamp),
            true
        );

        return orderId;
    }

    function cancelOrder(
        Side side,
        Price price,
        OrderId orderId
    ) external override {
        OrderQueueLib.OrderQueue storage queue = orderQueues[side][price];
        Order storage order = queue.orders[OrderId.unwrap(orderId)];

        if (order.user != msg.sender) revert UnauthorizedCancellation();

        Quantity remainingQuantity = Quantity.wrap(
            Quantity.unwrap(order.quantity) - Quantity.unwrap(order.filled)
        );

        queue.removeOrder(OrderId.unwrap(orderId));

        // Remove from user's active orders
        activeUserOrders[msg.sender].remove(
            OrderPacking.packOrder(side, price, OrderId.unwrap(orderId))
        );

        emit OrderCancelled(
            orderId,
            msg.sender,
            side,
            price,
            remainingQuantity,
            uint48(block.timestamp)
        );

        // Clean up empty price levels
        if (queue.isEmpty()) {
            priceTrees[side].remove(price);
            emit PriceLevelEmpty(side, price);
        }
    }

    // View functions
    function getBestPrice(Side side) external view override returns (Price) {
        return
            side == Side.BUY
                ? priceTrees[side].last()
                : priceTrees[side].first();
    }

    function getOrderQueue(
        Side side,
        Price price
    ) external view returns (uint256 orderCount, uint256 totalVolume) {
        OrderQueueLib.OrderQueue storage queue = orderQueues[side][price];
        (, , uint256 count, uint256 volume) = queue.getQueueInfo();
        return (count, volume);
    }

    function getUserActiveOrders(
        address user
    ) external view override returns (Order[] memory) {
        EnumerableSet.UintSet storage userOrders = activeUserOrders[user];
        Order[] memory orders = new Order[](userOrders.length());

        for (uint256 i = 0; i < userOrders.length(); i++) {
            (Side side, Price price, uint48 orderId) = OrderPacking.unpackOrder(
                userOrders.at(i)
            );
            orders[i] = orderQueues[side][price].getOrder(orderId);
        }

        return orders;
    }

    // Internal helper functions
    function _getNextBestPrice(
        Side side,
        Price price
    ) private view returns (Price) {
        if (RBTree.isEmpty(price)) {
            return
                side == Side.BUY
                    ? priceTrees[side].last()
                    : priceTrees[side].first();
        }
        return
            side == Side.BUY
                ? priceTrees[side].prev(price)
                : priceTrees[side].next(price);
    }

    function getNextBestPrices(
        Side side,
        Price price,
        uint8 count
    ) external view override returns (PriceVolume[] memory) {
        PriceVolume[] memory levels = new PriceVolume[](count);
        Price currentPrice = price;

        for (uint8 i = 0; i < count; i++) {
            currentPrice = _getNextBestPrice(side, currentPrice);
            if (RBTree.isEmpty(currentPrice)) break;

            levels[i] = PriceVolume({
                price: currentPrice,
                volume: orderQueues[side][currentPrice].totalVolume
            });
        }

        return levels;
    }
}
