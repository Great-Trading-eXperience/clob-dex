// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "./interfaces/IOrderBookErrors.sol";
import {OrderId, Quantity, Side, Status, OrderType, TimeInForce} from "./types/Types.sol";
import {BokkyPooBahsRedBlackTreeLibrary as RBTree, Price} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderQueueLib} from "./libraries/OrderQueueLib.sol";
import {OrderMatching} from "./libraries/OrderMatching.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PoolKey} from "./types/Pool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Currency} from "./types/Currency.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {PoolIdLibrary} from "./types/Pool.sol";

/// @title OrderBook - A Central Limit Order Book implementation
/// @notice Manages limit and market orders in a decentralized exchange
/// @dev Implements price-time priority matching with reentrance protection
contract OrderBook is Ownable, IOrderBook, ReentrancyGuard, IOrderBookErrors {
    using RBTree for RBTree.Tree;
    using OrderQueueLib for OrderQueueLib.OrderQueue;
    using OrderMatching for *;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => EnumerableSet.UintSet) private activeUserOrders;
    mapping(uint48 => OrderDetails) private orderDetailsMap;
    mapping(Side => RBTree.Tree) private priceTrees;
    mapping(Side => mapping(Price => OrderQueueLib.OrderQueue))
        private orderQueues;
    mapping(address => bool) private authorizedOperators; // To allow Routers or other contracts

    uint48 private constant EXPIRY_DAYS = 90 * 24 * 60 * 60; // 90 days in seconds
    uint8 private constant MAX_OPEN_LIMIT_ORDER = 100;
    address private balanceManager;
    address private router;
    uint48 private nextOrderId = 1;
    PoolKey private poolKey;
    bool private tradingPaused;
    TradingRules private tradingRules;

    constructor(
        address _poolManager,
        address _balanceManager,
        TradingRules memory _tradingRules,
        PoolKey memory _poolKey
    ) Ownable(_poolManager) {
        balanceManager = _balanceManager;
        tradingRules = _tradingRules;
        poolKey = _poolKey;
    }

    // Restrict access to authorized only
    modifier onlyRouter() {
        if (
            msg.sender != router &&
            msg.sender != owner() &&
            msg.sender != address(this)
        ) {
            revert UnauthorizedRouter(msg.sender);
        }
        _;
    }

    function getTradingRules() external view returns (TradingRules memory) {
        return tradingRules;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    /**
     * @notice Sets all trading rules at once
     * @param _tradingRules New trading rules to apply
     */
    function setTradingRules(
        TradingRules calldata _tradingRules
    ) external onlyOwner {
        tradingRules = _tradingRules;
    }

    /**
     * @notice Validates order parameters before processing
     * @dev Similar to TradePairs.addOrderChecks, this performs pre-trade validation
     * @param price The price of the order
     * @param quantity The quantity of the order
     * @param side The side of the order (BUY/SELL)
     * @param orderType Type of order (LIMIT or MARKET)
     * @return validatedPrice The validated price (may be adjusted for market orders)
     */
    function validateOrder(
        Price price,
        Quantity quantity,
        Side side,
        OrderType orderType,
        TimeInForce timeInForce
    ) private view returns (Price validatedPrice) {
        if (tradingPaused) {
            revert TradingPaused();
        }

        validateBasicOrderParameters(price, quantity, orderType);

        (uint256 orderAmount, uint256 quoteAmount) = calculateOrderAmounts(
            price,
            quantity,
            side,
            orderType
        );

        validateMinimumSizes(orderAmount, quoteAmount);

        // validateIncrements(orderAmount, quoteAmount, side, price);

        // Check price increments
        uint256 minPriceMove = Quantity.unwrap(tradingRules.minPriceMovement);
        if (Price.unwrap(price) % minPriceMove != 0) {
            revert InvalidPriceIncrement();
        }

        //TODO: Slippage check for market orders

        return
            orderType == OrderType.MARKET
                ? validateMarketOrder(side)
                : validateLimitOrder(price, side, timeInForce);
    }

    function validateBasicOrderParameters(
        Price price,
        Quantity quantity,
        OrderType orderType
    ) private pure {
        if (Quantity.unwrap(quantity) == 0) {
            revert InvalidQuantity();
        }

        if (orderType == OrderType.LIMIT && Price.unwrap(price) == 0) {
            revert InvalidPrice(Price.unwrap(price));
        }
    }

    function calculateOrderAmounts(
        Price price,
        Quantity quantity,
        Side side,
        OrderType orderType
    ) private view returns (uint256 orderAmount, uint256 quoteAmount) {
        orderAmount = Quantity.unwrap(quantity);

        if (orderType == OrderType.LIMIT) {
            quoteAmount = PoolIdLibrary.baseToQuote(
                orderAmount,
                Price.unwrap(price),
                poolKey.baseCurrency.decimals()
            );
        } else {
            Price bestOppositePrice = side == Side.SELL
                ? priceTrees[Side.BUY].last() // For SELL, get highest buy price
                : priceTrees[Side.SELL].first(); // For BUY, get lowest sell price

            if (RBTree.isEmpty(bestOppositePrice)) {
                revert OrderHasNoLiquidity();
            }

            quoteAmount = PoolIdLibrary.baseToQuote(
                orderAmount,
                Price.unwrap(bestOppositePrice),
                poolKey.baseCurrency.decimals()
            );
        }

        return (orderAmount, quoteAmount);
    }

    function validateMinimumSizes(
        uint256 orderAmount,
        uint256 quoteAmount
    ) private view {
        // Validate minimum order size (quote currency)
        uint256 minSize = Quantity.unwrap(tradingRules.minOrderSize);
        if (quoteAmount < minSize) {
            revert OrderTooSmall(quoteAmount, minSize);
        }

        // Validate minimum trade amount (base currency)
        uint256 minAmount = Quantity.unwrap(tradingRules.minTradeAmount);
        if (orderAmount < minAmount) {
            revert OrderTooSmall(orderAmount, minAmount);
        }
    }

    // function validateIncrements(
    //     uint256 orderAmount,
    //     uint256 quoteAmount,
    //     Side side,
    //     Price price
    // ) private view {
    //     // TODO: Check base currency amount increments (quantity)
    //     uint256 minAmountMove = Quantity.unwrap(tradingRules.minAmountMovement);
    //     if (orderAmount % minAmountMove != 0) {
    //         revert InvalidQuantityIncrement();
    //     }

    //     // TODO: Additional check for quote amount increments
    //     if (quoteAmount % minPriceMove != 0) {
    //         revert InvalidQuantityIncrement();
    //     }
    // }

    function validateMarketOrder(Side side) private view returns (Price) {
        Price bestOppositePrice = side == Side.BUY
            ? priceTrees[Side.SELL].first()
            : priceTrees[Side.BUY].last();

        if (RBTree.isEmpty(bestOppositePrice)) {
            revert OrderHasNoLiquidity();
        }

        // Calculate adjusted price with slippage
        Price adjustedPrice;
        if (side == Side.BUY) {
            adjustedPrice = Price.wrap(
                (Price.unwrap(bestOppositePrice) *
                    (100 + tradingRules.slippageTreshold)) / 100
            );
        } else {
            adjustedPrice = Price.wrap(
                (Price.unwrap(bestOppositePrice) *
                    (100 - tradingRules.slippageTreshold)) / 100
            );
        }

        return adjustedPrice;
    }

    function validateLimitOrder(
        Price price,
        Side side,
        TimeInForce timeInForce
    ) private view returns (Price) {
        // Check Post-Only (PO) condition
        if (timeInForce == TimeInForce.PO) {
            Price bestOppositePrice = side == Side.BUY
                ? priceTrees[Side.SELL].first()
                : priceTrees[Side.BUY].last();

            if (!RBTree.isEmpty(bestOppositePrice)) {
                bool wouldTake = side == Side.BUY
                    ? Price.unwrap(price) >= Price.unwrap(bestOppositePrice)
                    : Price.unwrap(price) <= Price.unwrap(bestOppositePrice);

                if (wouldTake) {
                    revert PostOnlyWouldTake();
                }
            }
        }

        return price;
    }

    /// @notice Places a new limit order
    /// @param price The price of the order
    /// @param quantity The quantity of the order
    /// @param side The side of the order (BUY/SELL)
    /// @param user The user placing the order
    /// @param timeInForce Time in force for the order (GTC, IOC, FOK, PO)
    /// @return orderId The ID of the placed order
    function placeOrder(
        Price price,
        Quantity quantity,
        Side side,
        address user,
        TimeInForce timeInForce
    ) external onlyRouter nonReentrant returns (OrderId) {
        validateOrder(price, quantity, side, OrderType.LIMIT, timeInForce);

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
            status: Status.OPEN,
            orderType: OrderType.LIMIT,
            side: side
        });

        orderQueues[side][price].addOrder(newOrder);

        if (!priceTrees[side].exists(price)) {
            priceTrees[side].insert(price);
        }

        activeUserOrders[user].add(OrderId.unwrap(orderId));

        // Store order details for direct lookup
        orderDetailsMap[OrderId.unwrap(orderId)] = OrderDetails({
            side: side,
            price: price,
            user: user,
            exists: true
        });

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

        uint256 amountToLock;
        Currency currencyToLock;

        if (side == Side.BUY) {
            amountToLock = PoolIdLibrary.baseToQuote(
                Quantity.unwrap(quantity),
                Price.unwrap(price),
                poolKey.baseCurrency.decimals()
            );
            currencyToLock = poolKey.quoteCurrency;
        } else {
            amountToLock = Quantity.unwrap(quantity);
            currencyToLock = poolKey.baseCurrency;
        }

        IBalanceManager(balanceManager).lock(
            user,
            currencyToLock,
            amountToLock
        );

        uint128 filled = 0;
        if (timeInForce != TimeInForce.PO) {
            OrderMatching.MatchOrder memory matchOrder = OrderMatching
                .MatchOrder({
                    order: newOrder,
                    side: side,
                    trader: user,
                    balanceManager: balanceManager,
                    poolKey: poolKey,
                    orderBook: this
                });

            filled = OrderMatching.matchOrder(
                matchOrder,
                orderQueues,
                priceTrees,
                false
            );
        }

        if (
            timeInForce == TimeInForce.FOK &&
            filled < uint128(Quantity.unwrap(quantity))
        ) {
            revert FillOrKillNotFulfilled(
                filled,
                uint128(Quantity.unwrap(quantity))
            );
        } else if (
            timeInForce == TimeInForce.IOC &&
            filled < uint128(Quantity.unwrap(quantity))
        ) {
            Order storage orderToCancel = orderQueues[side][price].orders[
                OrderId.unwrap(orderId)
            ];

            if (
                Quantity.unwrap(orderToCancel.quantity) >
                Quantity.unwrap(orderToCancel.filled)
            ) {
                _cancelOrder(side, price, orderId, user);
            }
        }

        unchecked {
            nextOrderId++;
        }

        return orderId;
    }

    /// @notice Places a new market order
    /// @param quantity The quantity of the order
    /// @param side The side of the order (BUY/SELL)
    /// @param user The user placing the order
    /// @return orderId The ID of the placed order
    function placeMarketOrder(
        Quantity quantity,
        Side side,
        address user
    ) external override onlyRouter nonReentrant returns (OrderId) {
        Price validatedPrice = validateOrder(
            Price.wrap(0),
            quantity,
            side,
            OrderType.MARKET,
            TimeInForce.GTC
        );

        OrderId orderId = OrderId.wrap(nextOrderId++);

        Order memory marketOrder = Order({
            id: orderId,
            user: user,
            next: OrderId.wrap(0),
            prev: OrderId.wrap(0),
            price: validatedPrice,
            timestamp: uint48(block.timestamp),
            quantity: quantity,
            filled: Quantity.wrap(0),
            expiry: uint48(block.timestamp + EXPIRY_DAYS),
            status: Status.OPEN,
            orderType: OrderType.MARKET,
            side: side
        });

        emit OrderPlaced(
            orderId,
            user,
            side,
            validatedPrice,
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
            poolKey: poolKey,
            orderBook: this
        });

        OrderMatching.matchOrder(matchOrder, orderQueues, priceTrees, true);

        return orderId;
    }

    function cancelOrder(
        OrderId orderId,
        address user
    ) external override onlyRouter {
        uint48 orderIdRaw = OrderId.unwrap(orderId);
        OrderDetails memory orderDetails = orderDetailsMap[orderIdRaw];

        if (!orderDetails.exists) {
            revert OrderNotFound();
        }

        _cancelOrder(orderDetails.side, orderDetails.price, orderId, user);
    }

    function _cancelOrder(
        Side side,
        Price price,
        OrderId orderId,
        address user
    ) internal {
        OrderQueueLib.OrderQueue storage queue = orderQueues[side][price];
        Order storage order = queue.orders[OrderId.unwrap(orderId)];

        if (order.user != user) revert UnauthorizedCancellation();

        Quantity remainingQuantity = Quantity.wrap(
            Quantity.unwrap(order.quantity) - Quantity.unwrap(order.filled)
        );

        queue.removeOrder(OrderId.unwrap(orderId));

        emit OrderMatching.UpdateOrder(
            orderId,
            uint48(block.timestamp),
            order.filled,
            Status.CANCELLED
        );
        emit OrderCancelled(
            orderId,
            user,
            uint48(block.timestamp),
            Status.CANCELLED
        );

        activeUserOrders[user].remove(OrderId.unwrap(orderId));

        // Remove order details from the map
        delete orderDetailsMap[OrderId.unwrap(orderId)];

        uint256 amountToUnlock;
        if (side == Side.BUY) {
            amountToUnlock = PoolIdLibrary.baseToQuote(
                Quantity.unwrap(remainingQuantity),
                Price.unwrap(price),
                poolKey.baseCurrency.decimals()
            );
        } else {
            amountToUnlock = Quantity.unwrap(remainingQuantity);
        }

        IBalanceManager(balanceManager).unlock(
            user,
            side == Side.BUY ? poolKey.quoteCurrency : poolKey.baseCurrency,
            amountToUnlock
        );

        if (queue.isEmpty()) {
            priceTrees[side].remove(price);
        }
    }

    function getBestPrice(
        Side side
    ) external view override returns (PriceVolume memory) {
        Price price = side == Side.BUY
            ? priceTrees[side].last()
            : priceTrees[side].first();

        return
            PriceVolume({
                price: price,
                volume: orderQueues[side][price].totalVolume
            });
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
                validVolume +=
                    uint128(Quantity.unwrap(order.quantity)) -
                    uint128(Quantity.unwrap(order.filled));
            }
            currentOrderId = uint48(OrderId.unwrap(order.next));
        }

        return (validOrderCount, validVolume);
    }

    function getUserActiveOrders(
        address user
    ) external view override returns (Order[] memory) {
        EnumerableSet.UintSet storage userOrders = activeUserOrders[user];
        Order[] memory orders = new Order[](userOrders.length());
        uint48 validOrderCount = 0;

        for (uint48 i = 0; i < userOrders.length(); i++) {
            uint48 orderId = uint48(userOrders.at(i));
            OrderDetails memory orderDetails = orderDetailsMap[orderId];

            if (!orderDetails.exists) {
                continue;
            }

            Order memory order = orderQueues[orderDetails.side][
                orderDetails.price
            ].getOrder(orderId);

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
}
