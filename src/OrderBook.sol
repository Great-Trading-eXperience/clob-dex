// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side, Status} from "./types/Types.sol";
import {
    BokkyPooBahsRedBlackTreeLibrary as RBTree,
    Price
} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderQueueLib} from "./libraries/OrderQueueLib.sol";
import {OrderMatching} from "./libraries/OrderMatching.sol";
import {OrderPacking} from "./libraries/OrderPacking.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PoolKey} from "./types/Pool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Currency} from "./types/Currency.sol";
// import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

/// @title OrderBook - A Central Limit Order Book implementation
/// @notice Manages limit and market orders in a decentralized exchange
/// @dev Implements price-time priority matching with reentrance protection
contract OrderBook is Ownable, IOrderBook, ReentrancyGuard {
    uint256 constant EXPIRY_DAYS = 90 * 24 * 60 * 60; // 90 days in seconds

    using RBTree for RBTree.Tree;
    using OrderQueueLib for OrderQueueLib.OrderQueue;
    using OrderMatching for *;
    using EnumerableSet for EnumerableSet.UintSet;
    using OrderPacking for *;

    error UnauthorizedCancellation();
    error InvalidPrice(uint256 price);
    error InvalidQuantity();
    error UnauthorizedRouter(address reouter);

    mapping(address => EnumerableSet.UintSet) private activeUserOrders;
    mapping(Side => RBTree.Tree) private priceTrees;
    mapping(Side => mapping(Price => OrderQueueLib.OrderQueue)) private orderQueues;
    mapping(address => bool) private authorizedOperators; // To allow Routers or other contracts

    uint48 private nextOrderId = 1;
    address private balanceManager;
    address private router;
    uint256 private maxOrderAmount;
    uint256 private lotSize;
    PoolKey private poolKey;

    constructor(
        address _poolManager,
        address _balanceManager,
        uint256 _maxOrderAmount,
        uint256 _lotSize,
        PoolKey memory _poolKey
    ) Ownable(_poolManager) {
        balanceManager = _balanceManager;
        maxOrderAmount = _maxOrderAmount;
        lotSize = _lotSize;
        poolKey = _poolKey;
    }

    // Restrict access to authorized only
    modifier onlyRouter() {
        if (msg.sender != router && msg.sender != owner()) {
            revert UnauthorizedRouter(msg.sender);
        }
        _;
    }

    // Set authorized operators (e.g., Router)
    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    /// @notice Places a new limit order
    /// @param price The price of the order
    /// @param quantity The quantity of the order
    /// @param side The side of the order (BUY/SELL)
    /// @return orderId The ID of the placed order
    function placeOrder(
        Price price,
        Quantity quantity,
        Side side,
        address user
    ) external override onlyRouter nonReentrant returns (OrderId) {
        if (Quantity.unwrap(quantity) == 0) revert InvalidQuantity();
        if (Price.unwrap(price) == 0) revert InvalidPrice(Price.unwrap(price));

        OrderId orderId = OrderId.wrap(nextOrderId);

        Order memory newOrder = Order({
            id: orderId,
            user: user,
            next: OrderId.wrap(0),
            prev: OrderId.wrap(0),
            price: price,
            timestamp: uint48(block.timestamp),
            quantity: quantity,
            filled: Quantity.wrap(0),
            expiry: uint48(block.timestamp + EXPIRY_DAYS),
            status: Status.OPEN
        });

        orderQueues[side][price].addOrder(newOrder);

        if (!priceTrees[side].exists(price)) {
            priceTrees[side].insert(price);
        }

        activeUserOrders[user].add(OrderPacking.packOrder(side, price, OrderId.unwrap(orderId)));

        emit OrderPlaced(
            orderId,
            user,
            side,
            price,
            quantity,
            uint48(block.timestamp),
            newOrder.expiry,
            false,
            Status.OPEN
        );

        // Lock balance
        (Currency currency, uint256 amount) =
            poolKey.calculateAmountAndCurrency(price, quantity, side);
        IBalanceManager(balanceManager).lock(user, currency, amount);

        OrderMatching.MatchOrder memory matchOrder = OrderMatching.MatchOrder({
            order: newOrder,
            side: side,
            trader: user,
            balanceManager: balanceManager,
            poolKey: poolKey
        });

        OrderMatching.matchOrder(matchOrder, orderQueues, priceTrees, false);

        unchecked {
            nextOrderId++;
        }

        return orderId;
    }

    /// @notice Places a new market order
    /// @param quantity The quantity of the order
    /// @param side The side of the order (BUY/SELL)
    /// @return orderId The ID of the placed order
    function placeMarketOrder(
        Quantity quantity,
        Side side,
        address user
    ) external override onlyRouter nonReentrant returns (OrderId) {
        if (Quantity.unwrap(quantity) == 0) revert InvalidQuantity();

        OrderId orderId = OrderId.wrap(nextOrderId++);

        Order memory marketOrder = Order({
            id: orderId,
            user: user,
            next: OrderId.wrap(0),
            prev: OrderId.wrap(0),
            price: Price.wrap(0),
            timestamp: uint48(block.timestamp),
            quantity: quantity,
            filled: Quantity.wrap(0),
            expiry: uint48(block.timestamp + EXPIRY_DAYS),
            status: Status.OPEN
        });

        emit OrderPlaced(
            orderId,
            msg.sender,
            side,
            Price.wrap(0),
            quantity,
            uint48(block.timestamp),
            marketOrder.expiry,
            true,
            Status.OPEN
        );

        OrderMatching.MatchOrder memory matchOrder = OrderMatching.MatchOrder({
            order: marketOrder,
            side: side,
            trader: user,
            balanceManager: balanceManager,
            poolKey: poolKey
        });

        OrderMatching.matchOrder(matchOrder, orderQueues, priceTrees, true);

        return orderId;
    }

    function cancelOrder(
        Side side,
        Price price,
        OrderId orderId,
        address user
    ) external override onlyRouter {
        OrderQueueLib.OrderQueue storage queue = orderQueues[side][price];
        Order storage order = queue.orders[OrderId.unwrap(orderId)];

        if (order.user != user) revert UnauthorizedCancellation();

        // Remove the order from the queue
        queue.removeOrder(OrderId.unwrap(orderId));

        // Emit event for order update and cancellation
        emit OrderMatching.UpdateOrder(
            orderId, uint48(block.timestamp), order.filled, Status.CANCELLED
        );
        emit OrderCancelled(orderId, user, uint48(block.timestamp), Status.CANCELLED);

        // Remove the order from active user orders
        activeUserOrders[user].remove(OrderPacking.packOrder(side, price, OrderId.unwrap(orderId)));

        Quantity remainingQuantity =
            Quantity.wrap(Quantity.unwrap(order.quantity) - Quantity.unwrap(order.filled));
        (Currency currency, uint256 amount) =
            poolKey.calculateAmountAndCurrency(price, remainingQuantity, side);
        IBalanceManager(balanceManager).unlock(user, currency, amount);

        // Remove price from price tree if the queue is empty
        if (queue.isEmpty()) {
            priceTrees[side].remove(price);
        }
    }

    function getBestPrice(Side side) external view override returns (PriceVolume memory) {
        Price price = side == Side.BUY ? priceTrees[side].last() : priceTrees[side].first();

        return PriceVolume({price: price, volume: orderQueues[side][price].totalVolume});
    }

    function getOrderQueue(
        Side side,
        Price price
    ) external view returns (uint48 orderCount, uint256 totalVolume) {
        OrderQueueLib.OrderQueue storage queue = orderQueues[side][price];
        uint48 validOrderCount = 0;
        uint256 validVolume = 0;

        uint48 currentOrderId = queue.head;
        while (currentOrderId != 0) {
            Order storage order = queue.orders[currentOrderId];
            if (order.expiry > block.timestamp) {
                validOrderCount++;
                validVolume += uint128(Quantity.unwrap(order.quantity))
                    - uint128(Quantity.unwrap(order.filled));
            }
            currentOrderId = uint48(OrderId.unwrap(order.next));
        }

        return (validOrderCount, validVolume);
    }

    function getUserActiveOrders(address user) external view override returns (Order[] memory) {
        EnumerableSet.UintSet storage userOrders = activeUserOrders[user];
        Order[] memory orders = new Order[](userOrders.length());
        uint48 validOrderCount = 0;

        for (uint48 i = 0; i < userOrders.length(); i++) {
            (Side side, Price price, uint48 orderId) = OrderPacking.unpackOrder(userOrders.at(i));
            Order memory order = orderQueues[side][price].getOrder(orderId);

            if (order.expiry <= block.timestamp) {
                continue;
            }

            orders[validOrderCount] = order;
            validOrderCount++;
        }

        assembly {
            mstore(orders, validOrderCount)
        }

        return orders;
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

    function _getNextBestPrice(Side side, Price price) private view returns (Price) {
        if (RBTree.isEmpty(price)) {
            return side == Side.BUY ? priceTrees[side].last() : priceTrees[side].first();
        }
        return side == Side.BUY ? priceTrees[side].prev(price) : priceTrees[side].next(price);
    }
}
