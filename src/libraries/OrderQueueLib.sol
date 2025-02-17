// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side} from "../types/Types.sol";
import {IERC6909Lock} from "../interfaces/external/IERC6909Lock.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @title OrderQueueLib - A library for managing order queues
/// @notice Provides functionality for maintaining price-time priority queues
/// @dev Implements a doubly linked list structure for order management
library OrderQueueLib {
    error OrderNotFound();
    error QueueEmpty();

    struct OrderQueue {
        uint48 head;
        uint48 tail;
        uint48 orderCount;
        uint256 totalVolume;
        mapping(uint48 => IOrderBook.Order) orders;
    }

    /// @notice Adds a new order to the queue
    /// @param queue The order queue to add to
    /// @param order The order to add
    /// @return success Whether the operation was successful
    function addOrder(OrderQueue storage queue, IOrderBook.Order memory order) internal returns (bool) {
        uint48 orderId = OrderId.unwrap(order.id);
        queue.orders[orderId] = order;

        if (queue.head == 0) {
            queue.head = orderId;
            queue.tail = orderId;
        } else {
            queue.orders[queue.tail].next = OrderId.wrap(orderId);
            queue.orders[orderId].prev = OrderId.wrap(queue.tail);
            queue.tail = orderId;
        }

        unchecked {
            queue.totalVolume += uint128(Quantity.unwrap(order.quantity));
            queue.orderCount++;
        }

        return true;
    }

    /// @notice Removes an order from the queue
    /// @param queue The order queue to remove from
    /// @param orderId The ID of the order to remove
    /// @return remainingQuantity The remaining quantity of the removed order
    function removeOrder(OrderQueue storage queue, uint48 orderId) internal returns (uint256) {
        if (queue.orderCount == 0) revert QueueEmpty();

        IOrderBook.Order storage order = queue.orders[orderId];
        if (OrderId.unwrap(order.id) == 0 || Quantity.unwrap(order.quantity) == 0) revert OrderNotFound();

        uint256 remainingQuantity = Quantity.unwrap(order.quantity) - Quantity.unwrap(order.filled);

        if (OrderId.unwrap(order.prev) != 0) {
            queue.orders[uint48(OrderId.unwrap(order.prev))].next = order.next;
        } else {
            queue.head = uint48(OrderId.unwrap(order.next));
        }

        if (OrderId.unwrap(order.next) != 0) {
            queue.orders[uint48(OrderId.unwrap(order.next))].prev = order.prev;
        } else {
            queue.tail = uint48(OrderId.unwrap(order.prev));
        }

        queue.orderCount--;
        queue.totalVolume -= remainingQuantity;

        delete queue.orders[orderId];

        return remainingQuantity;
    }

    function getOrder(OrderQueue storage queue, uint48 orderId) internal view returns (IOrderBook.Order memory) {
        return queue.orders[orderId];
    }

    function isEmpty(OrderQueue storage queue) internal view returns (bool) {
        return queue.orderCount == 0;
    }
}
