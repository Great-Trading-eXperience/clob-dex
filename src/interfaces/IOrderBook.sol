// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IOrderBook {
    enum Side {
        BUY,
        SELL
    }

    enum Status {
        OPEN,
        PARTIALLY_FILLED,
        FILLED,
        CANCELLED,
        REJECTED,
        EXPIRED
    }

    enum OrderType {
        LIMIT,
        MARKET
    }

    enum TimeInForce {
        GTC,
        IOC,
        FOK,
        PO
    }

    struct Order {
        // Slot 1
        address user;
        uint48 id;
        uint48 next;
        // Slot 2
        uint128 quantity;
        uint128 filled;
        // Slot 3
        uint128 price;
        uint48 prev;
        uint48 expiry;
        Status status;
        OrderType orderType;
        Side side;
    }

    struct OrderQueue {
        uint256 totalVolume;
        uint48 orderCount;
        uint48 head;
        uint48 tail;
    }

    struct TradingRules {
        uint128 minTradeAmount;
        uint128 minAmountMovement;
        uint128 minPriceMovement;
        uint128 minOrderSize;
    }

    struct PriceVolume {
        uint128 price;
        uint256 volume;
    }

    struct MatchOrder {
        IOrderBook.Order order;
        IOrderBook.Side side;
        address trader;
        address balanceManager;
        IOrderBook orderBook;
    }

    event OrderPlaced(
        uint48 indexed orderId,
        address indexed user,
        Side indexed side,
        uint128 price,
        uint128 quantity,
        uint48 expiry,
        bool isMarketOrder,
        Status status
    );

    event OrderMatched(
        address indexed user,
        uint48 indexed buyOrderId,
        uint48 indexed sellOrderId,
        IOrderBook.Side side,
        uint48 timestamp,
        uint128 executionPrice,
        uint128 executedQuantity
    );

    event UpdateOrder(uint48 indexed orderId, uint48 timestamp, uint128 filled, IOrderBook.Status status);

    event OrderCancelled(uint48 indexed orderId, address indexed user, uint48 timestamp, Status status);

    function setRouter(
        address router
    ) external;

    function placeOrder(
        uint128 price,
        uint128 quantity,
        Side side,
        address user,
        TimeInForce timeInForce
    ) external returns (uint48 orderId);

    function getOrder(
        uint48 orderId
    ) external view returns (Order memory order);

    function placeMarketOrder(uint128 quantity, Side side, address user) external returns (uint48);

    function cancelOrder(uint48 orderId, address user) external;

    function getOrderQueue(Side side, uint128 price) external view returns (uint48 orderCount, uint256 totalVolume);

    function getBestPrice(
        Side side
    ) external view returns (PriceVolume memory);

    function getNextBestPrices(Side side, uint128 price, uint8 count) external view returns (PriceVolume[] memory);

    function setTradingRules(
        TradingRules calldata tradingRules
    ) external;

    function getTradingRules() external view returns (TradingRules memory);
}
