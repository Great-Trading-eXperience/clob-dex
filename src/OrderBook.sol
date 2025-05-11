// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IOrderBookErrors} from "./interfaces/IOrderBookErrors.sol";
import {Currency} from "./libraries/Currency.sol";
import {PoolKey} from "./libraries/Pool.sol";
import {PoolIdLibrary} from "./libraries/Pool.sol";

import {OrderBookStorage} from "./storages/OrderBookStorage.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {RedBlackTreeLib} from "@solady/utils/RedBlackTreeLib.sol";

contract OrderBook is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IOrderBook,
    IOrderBookErrors,
    OrderBookStorage
{
    using RedBlackTreeLib for RedBlackTreeLib.Tree;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyRouter() {
        Storage storage $ = getStorage();
        if (msg.sender != $.router && msg.sender != owner() && msg.sender != address(this)) {
            revert UnauthorizedRouter(msg.sender);
        }
        _;
    }

    function initialize(
        address _poolManager,
        address _balanceManager,
        TradingRules memory _tradingRules,
        PoolKey memory _poolKey
    ) public initializer {
        __Ownable_init(_poolManager);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.balanceManager = _balanceManager;
        $.tradingRules = _tradingRules;
        $.poolKey = _poolKey;
        $.nextOrderId = 1;
        $.expiryDays = 90 days;
    }

    function getTradingRules() external view returns (TradingRules memory) {
        Storage storage $ = getStorage();
        return $.tradingRules;
    }

    function setRouter(
        address _router
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.router = _router;
    }

    function setTradingRules(
        TradingRules calldata _tradingRules
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.tradingRules = _tradingRules;
    }

    function validateOrder(
        uint128 price,
        uint128 quantity,
        Side side,
        OrderType orderType,
        TimeInForce timeInForce
    ) private view {
        Storage storage $ = getStorage();
        validateBasicOrderParameters(price, quantity, orderType);

        (uint256 orderAmount, uint256 quoteAmount) = calculateOrderAmounts(price, quantity, side, orderType);

        validateMinimumSizes(orderAmount, quoteAmount);

        // Check price increments
        uint256 minPriceMove = $.tradingRules.minPriceMovement;
        if (price % minPriceMove != 0) {
            revert InvalidPriceIncrement();
        }

        if (orderType == OrderType.LIMIT) {
            validateLimitOrder(price, side, timeInForce);
        }
    }

    function validateBasicOrderParameters(uint128 price, uint128 quantity, OrderType orderType) private pure {
        if (quantity == 0) {
            revert InvalidQuantity();
        }

        if (orderType == OrderType.LIMIT && price == 0) {
            revert InvalidPrice(price);
        }
    }

    function calculateOrderAmounts(
        uint128 price,
        uint128 quantity,
        Side side,
        OrderType orderType
    ) private view returns (uint256 orderAmount, uint256 quoteAmount) {
        Storage storage $ = getStorage();
        orderAmount = quantity;

        if (orderType == OrderType.LIMIT) {
            quoteAmount = PoolIdLibrary.baseToQuote(orderAmount, price, $.poolKey.baseCurrency.decimals());
        } else {
            bytes32 bestOppositePricePtr =
                side == Side.SELL ? $.priceTrees[Side.BUY].last() : $.priceTrees[Side.SELL].first();
            uint128 bestOppositePrice = uint128(RedBlackTreeLib.value(bestOppositePricePtr));

            if (bestOppositePrice == 0) {
                revert OrderHasNoLiquidity();
            }

            quoteAmount = PoolIdLibrary.baseToQuote(orderAmount, bestOppositePrice, $.poolKey.baseCurrency.decimals());
        }

        return (orderAmount, quoteAmount);
    }

    function validateMinimumSizes(uint256 orderAmount, uint256 quoteAmount) private view {
        Storage storage $ = getStorage();
        // Validate minimum order size (quote currency)
        uint256 minSize = $.tradingRules.minOrderSize;

        if (quoteAmount < minSize) {
            revert OrderTooSmall(quoteAmount, minSize);
        }

        // Validate minimum trade amount (base currency)
        uint256 minAmount = $.tradingRules.minTradeAmount;
        if (orderAmount < minAmount) {
            revert OrderTooSmall(orderAmount, minAmount);
        }
    }

    function validateLimitOrder(uint128 price, Side side, TimeInForce timeInForce) private view returns (uint128) {
        Storage storage $ = getStorage();
        if (timeInForce == TimeInForce.PO) {
            bytes32 bestOppositePricePtr =
                side == Side.BUY ? $.priceTrees[Side.SELL].first() : $.priceTrees[Side.BUY].last();
            uint128 bestOppositePrice = uint128(RedBlackTreeLib.value(bestOppositePricePtr));

            if (bestOppositePrice != 0) {
                bool wouldTake = side == Side.BUY ? price >= bestOppositePrice : price <= bestOppositePrice;

                if (wouldTake) {
                    revert PostOnlyWouldTake();
                }
            }
        }

        return price;
    }

    function placeOrder(
        uint128 price,
        uint128 quantity,
        Side side,
        address user,
        TimeInForce timeInForce
    ) external onlyRouter returns (uint48 orderId) {
        Storage storage $ = getStorage();
        validateOrder(price, quantity, side, OrderType.LIMIT, timeInForce);

        orderId = $.nextOrderId;

        Order memory newOrder = Order({
            id: orderId,
            user: user,
            next: 0,
            prev: 0,
            price: price,
            quantity: quantity,
            filled: 0,
            expiry: uint48(block.timestamp + $.expiryDays),
            status: Status.OPEN,
            orderType: OrderType.LIMIT,
            side: side
        });

        _lockOrderAmount(user, side, price, quantity);

        _addOrderToQueue(newOrder);

        emit OrderPlaced(orderId, user, side, price, quantity, newOrder.expiry, false, Status.OPEN);

        _handleTimeInForce(newOrder, side, user, timeInForce);

        unchecked {
            $.nextOrderId++;
        }

        return orderId;
    }

    function _lockOrderAmount(address user, Side side, uint128 price, uint128 quantity) private {
        Storage storage $ = getStorage();
        PoolKey memory poolKey = $.poolKey;

        uint256 amountToLock;
        Currency currencyToLock;

        if (side == Side.BUY) {
            amountToLock = PoolIdLibrary.baseToQuote(quantity, price, poolKey.baseCurrency.decimals());
            currencyToLock = poolKey.quoteCurrency;
        } else {
            amountToLock = quantity;
            currencyToLock = poolKey.baseCurrency;
        }

        IBalanceManager($.balanceManager).lock(user, currencyToLock, amountToLock);
    }

    function _handleTimeInForce(
        Order memory order,
        Side side,
        address user,
        TimeInForce timeInForce
    ) private returns (uint128 filled) {
        Storage storage $ = getStorage();
        filled = 0;

        if (timeInForce != TimeInForce.PO) {
            filled = _matchOrder(order, side, user, false);
        }

        $.orders[order.id].filled = filled;
        $.orderQueues[side][order.price].totalVolume -= filled;

        if (filled == order.quantity) {
            _removeOrderFromQueue($.orderQueues[side][order.price], $.orders[order.id]);
            emit UpdateOrder(order.id, uint48(block.timestamp), filled, Status.FILLED);
        }

        if (timeInForce == TimeInForce.FOK && filled < uint128(order.quantity)) {
            revert FillOrKillNotFulfilled(filled, uint128(order.quantity));
        } else if (timeInForce == TimeInForce.IOC && filled < uint128(order.quantity)) {
            Order storage orderToCancel = $.orders[order.id];
            if (orderToCancel.quantity > orderToCancel.filled) {
                _cancelOrder(order.id, user);
            }
        }

        return filled;
    }

    function placeMarketOrder(
        uint128 quantity,
        Side side,
        address user
    ) external onlyRouter nonReentrant returns (uint48 orderId) {
        Storage storage $ = getStorage();
        validateOrder(0, quantity, side, OrderType.MARKET, TimeInForce.GTC);

        orderId = $.nextOrderId;

        Order memory marketOrder = Order({
            id: orderId,
            user: user,
            next: 0,
            prev: 0,
            price: 0,
            quantity: quantity,
            filled: 0,
            expiry: uint48(block.timestamp + $.expiryDays),
            status: Status.OPEN,
            orderType: OrderType.MARKET,
            side: side
        });

        emit OrderPlaced(orderId, user, side, 0, quantity, marketOrder.expiry, true, Status.OPEN);

        _matchOrder(marketOrder, side, user, true);

        unchecked {
            $.nextOrderId++;
        }

        return orderId;
    }

    function cancelOrder(uint48 orderId, address user) external onlyRouter {
        _cancelOrder(orderId, user);
    }

    function _cancelOrder(uint48 orderId, address user) private {
        Storage storage $ = getStorage();
        Order storage order = $.orders[orderId];
        IOrderBook.OrderQueue storage queue = $.orderQueues[order.side][order.price];

        if (order.user != user) {
            revert UnauthorizedCancellation();
        }

        uint128 remainingQuantity = order.quantity - order.filled;

        _removeOrderFromQueue(queue, order);

        emit OrderCancelled(orderId, user, uint48(block.timestamp), Status.CANCELLED);

        uint256 amountToUnlock;
        if (order.side == Side.BUY) {
            amountToUnlock =
                PoolIdLibrary.baseToQuote(remainingQuantity, order.price, $.poolKey.baseCurrency.decimals());
        } else {
            amountToUnlock = remainingQuantity;
        }

        IBalanceManager($.balanceManager).unlock(
            user, order.side == Side.BUY ? $.poolKey.quoteCurrency : $.poolKey.baseCurrency, amountToUnlock
        );

        if (isQueueEmpty(order.side, order.price)) {
            RedBlackTreeLib.remove($.priceTrees[order.side], order.price);
        }
    }

    function getBestPrice(
        Side side
    ) external view override returns (PriceVolume memory) {
        Storage storage $ = getStorage();
        bytes32 pricePtr = side == Side.BUY ? $.priceTrees[side].last() : $.priceTrees[side].first();
        uint128 price = uint128(RedBlackTreeLib.value(pricePtr));

        return PriceVolume({price: price, volume: $.orderQueues[side][price].totalVolume});
    }

    function getOrderQueue(Side side, uint128 price) external view returns (uint48 orderCount, uint256 totalVolume) {
        Storage storage $ = getStorage();
        IOrderBook.OrderQueue storage queue = $.orderQueues[side][price];
        return (queue.orderCount, queue.totalVolume);
    }

    function getOrder(
        uint48 orderId
    ) external view returns (Order memory) {
        Storage storage $ = getStorage();
        return $.orders[orderId];
    }

    function _handleExpiredOrder(IOrderBook.OrderQueue storage queue, IOrderBook.Order storage order) private {
        _removeOrderFromQueue(queue, order);
        emit UpdateOrder(order.id, uint48(block.timestamp), 0, Status.EXPIRED);
    }

    function _processMatchingOrder(
        Order memory originalOrder,
        Order storage matchingOrder,
        OrderQueue storage queue,
        uint128 bestPrice,
        uint128 remaining,
        uint128 filled,
        Side side,
        address user,
        bool isMarketOrder
    ) private returns (uint128, uint128) {
        uint128 matchingRemaining = matchingOrder.quantity - matchingOrder.filled;
        uint128 executedQuantity = remaining < matchingRemaining ? remaining : matchingRemaining;

        remaining -= executedQuantity;
        filled += executedQuantity;

        matchingOrder.filled += executedQuantity;
        queue.totalVolume -= executedQuantity;

        transferBalances(user, matchingOrder.user, bestPrice, executedQuantity, side, isMarketOrder);

        if (matchingOrder.filled == matchingOrder.quantity) {
            _removeOrderFromQueue(queue, matchingOrder);
        }

        emit OrderMatched(
            user,
            side == Side.BUY ? originalOrder.id : matchingOrder.id,
            side == Side.SELL ? originalOrder.id : matchingOrder.id,
            side,
            uint48(block.timestamp),
            bestPrice,
            executedQuantity
        );

        return (remaining, filled);
    }

    function _updatePriceLevel(
        uint128 bestPrice,
        OrderQueue storage queue,
        RedBlackTreeLib.Tree storage priceTree
    ) private {
        if (queue.orderCount == 0 && priceTree.exists(bestPrice)) {
            priceTree.remove(bestPrice);
        }
    }

    function _matchOrder(
        Order memory order,
        Side side,
        address user,
        bool isMarketOrder
    ) private returns (uint128 filled) {
        Storage storage $ = getStorage();
        Side oppositeSide = side == Side.BUY ? Side.SELL : Side.BUY;
        RedBlackTreeLib.Tree storage priceTree = $.priceTrees[oppositeSide];

        uint128 remaining = order.quantity - order.filled;
        uint128 orderPrice = order.price;
        uint128 latestBestPrice = 0;
        uint128 previousRemaining = 0;
        filled = 0;

        while (remaining > 0) {
            uint128 bestPrice = _getBestMatchingPrice(orderPrice, oppositeSide, isMarketOrder);

            if (bestPrice == 0) {
                break;
            }

            if (bestPrice == latestBestPrice && previousRemaining == remaining) {
                bytes32 bestPricePtr = priceTree.find(bestPrice);
                bestPrice = side == Side.BUY
                    ? uint128(RedBlackTreeLib.value(RedBlackTreeLib.next(bestPricePtr)))
                    : uint128(RedBlackTreeLib.value(RedBlackTreeLib.prev(bestPricePtr)));

                if (bestPrice == 0) {
                    break;
                }
            }

            latestBestPrice = bestPrice;
            previousRemaining = remaining;
            OrderQueue storage queue = $.orderQueues[oppositeSide][bestPrice];
            uint48 currentOrderId = queue.head;

            while (currentOrderId != 0 && remaining > 0) {
                Order storage matchingOrder = $.orders[currentOrderId];
                uint48 nextOrderId = matchingOrder.next;

                if (matchingOrder.expiry < block.timestamp) {
                    _handleExpiredOrder(queue, matchingOrder);
                } else if (matchingOrder.user == user) {
                    _cancelOrder(currentOrderId, user);
                } else {
                    (remaining, filled) = _processMatchingOrder(
                        order, matchingOrder, queue, bestPrice, remaining, filled, side, user, isMarketOrder
                    );
                }
                currentOrderId = nextOrderId;
            }

            _updatePriceLevel(bestPrice, queue, priceTree);
        }

        return filled;
    }

    function getNextBestPrices(
        Side side,
        uint128 price,
        uint8 count
    ) external view override returns (PriceVolume[] memory) {
        Storage storage $ = getStorage();
        PriceVolume[] memory levels = new PriceVolume[](count);
        uint128 currentPrice = price;

        for (uint8 i = 0; i < count; i++) {
            currentPrice = _getNextBestPrice(side, currentPrice);
            if (currentPrice == 0) {
                break;
            }

            levels[i] = PriceVolume({price: currentPrice, volume: $.orderQueues[side][currentPrice].totalVolume});
        }

        return levels;
    }

    function _getNextBestPrice(Side side, uint128 price) private view returns (uint128) {
        Storage storage $ = getStorage();
        RedBlackTreeLib.Tree storage priceTree = $.priceTrees[side];

        bytes32 pricePtr;
        if (price == 0) {
            // Get the first or last price based on the side
            pricePtr = side == Side.BUY ? priceTree.last() : priceTree.first();
        } else {
            // Find the pointer for the current price
            bytes32 currentPricePtr = priceTree.find(uint256(price));
            // Traverse to the next or previous price based on the side
            pricePtr = side == Side.BUY ? RedBlackTreeLib.prev(currentPricePtr) : RedBlackTreeLib.next(currentPricePtr);
        }

        // Return the price value if the pointer is valid
        return pricePtr != bytes32(0) ? uint128(RedBlackTreeLib.value(pricePtr)) : 0;
    }

    function _getBestMatchingPrice(
        uint128 orderPrice,
        IOrderBook.Side side,
        bool isMarketOrder
    ) private view returns (uint128) {
        Storage storage $ = getStorage();
        RedBlackTreeLib.Tree storage priceTree = $.priceTrees[side];

        bytes32 pricePtr = side == IOrderBook.Side.BUY ? priceTree.last() : priceTree.first();
        uint128 bestPrice = uint128(RedBlackTreeLib.value(pricePtr));

        if (bestPrice > 0) {
            return bestPrice;
        }

        return priceTree.exists(orderPrice) ? orderPrice : 0;
    }

    function transferBalances(
        address trader,
        address matchingUser,
        uint128 matchPrice,
        uint128 executedQuantity,
        IOrderBook.Side side,
        bool isMarketOrder
    ) private {
        Storage storage $ = getStorage();
        uint256 baseAmount = executedQuantity;

        uint256 quoteAmount = PoolIdLibrary.baseToQuote(baseAmount, matchPrice, $.poolKey.baseCurrency.decimals());

        if (side == IOrderBook.Side.SELL) {
            if (!isMarketOrder) {
                IBalanceManager($.balanceManager).unlock(trader, $.poolKey.baseCurrency, baseAmount);
            }

            IBalanceManager($.balanceManager).transferFrom(trader, matchingUser, $.poolKey.baseCurrency, baseAmount);

            IBalanceManager($.balanceManager).transferLockedFrom(
                matchingUser, trader, $.poolKey.quoteCurrency, quoteAmount
            );
        } else {
            if (!isMarketOrder) {
                IBalanceManager($.balanceManager).unlock(trader, $.poolKey.quoteCurrency, quoteAmount);
            }
            IBalanceManager($.balanceManager).transferFrom(trader, matchingUser, $.poolKey.quoteCurrency, quoteAmount);
            IBalanceManager($.balanceManager).transferLockedFrom(
                matchingUser, trader, $.poolKey.baseCurrency, baseAmount
            );
        }
    }

    function _addOrderToQueue(
        IOrderBook.Order memory _order
    ) private {
        Storage storage $ = getStorage();
        IOrderBook.OrderQueue storage queue = $.orderQueues[_order.side][_order.price];
        Order storage order = $.orders[_order.id];

        order.id = _order.id;
        order.user = _order.user;
        order.next = _order.next;
        order.prev = _order.prev;
        order.price = _order.price;
        order.quantity = _order.quantity;
        order.filled = _order.filled;
        order.expiry = _order.expiry;
        order.status = _order.status;
        order.orderType = _order.orderType;
        order.side = _order.side;

        if (queue.head == 0) {
            queue.head = _order.id;
            queue.tail = _order.id;
        } else {
            $.orders[queue.tail].next = _order.id;
            order.prev = queue.tail;
            queue.tail = _order.id;
        }

        unchecked {
            queue.totalVolume += uint256(_order.quantity);
            queue.orderCount++;
        }

        RedBlackTreeLib.Tree storage priceTree = $.priceTrees[_order.side];

        if (!RedBlackTreeLib.exists(priceTree, uint256(_order.price))) {
            RedBlackTreeLib.insert(priceTree, (_order.price));
        }
    }

    function _removeOrderFromQueue(
        IOrderBook.OrderQueue storage queue,
        IOrderBook.Order storage order
    ) private returns (uint256) {
        Storage storage $ = getStorage();

        if (queue.orderCount == 0) {
            revert QueueEmpty();
        }

        uint256 remainingQuantity = order.quantity - order.filled;

        // Update queue pointers
        if (order.prev != 0) {
            $.orders[order.prev].next = order.next;
        } else {
            queue.head = order.next;
        }

        if (order.next != 0) {
            $.orders[order.next].prev = order.prev;
        } else {
            queue.tail = order.prev;
        }

        queue.orderCount--;
        queue.totalVolume -= remainingQuantity;

        return remainingQuantity;
    }

    function isQueueEmpty(IOrderBook.Side side, uint128 price) private view returns (bool) {
        Storage storage $ = getStorage();
        return $.orderQueues[side][price].orderCount == 0;
    }
}
