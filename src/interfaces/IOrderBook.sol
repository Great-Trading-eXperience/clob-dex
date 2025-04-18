// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OrderId, Quantity, Side, Status, TimeInForce, OrderType} from "../types/Types.sol";
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {PoolKey} from "../types/Pool.sol";
import {Currency} from "../types/Currency.sol";

interface IOrderBook {
    struct Order {
        address user;
        OrderId id;
        OrderId next;
        OrderId prev;
        uint48 timestamp;
        uint48 expiry;
        Quantity quantity;
        Quantity filled;
        Price price;
        Status status;
        OrderType orderType;
        Side side;
    }

    struct OrderDetails {
        Side side;
        Price price;
        address user;
        bool exists;
    }

    struct TradingRules {
        Quantity minTradeAmount;
        Quantity minAmountMovement;
        Quantity minPriceMovement;
        Quantity minOrderSize;
        uint8 slippageTreshold;
    }

    struct PriceVolume {
        Price price;
        uint256 volume;
    }

    event OrderPlaced(
        OrderId indexed orderId,
        address indexed user,
        Side indexed side,
        Price price,
        Quantity quantity,
        uint48 timestamp,
        uint48 expiry,
        bool isMarketOrder,
        Status status
    );

    event OrderCancelled(
        OrderId indexed orderId,
        address indexed user,
        uint48 timestamp,
        Status status
    );

    function setRouter(address router) external;

    function placeOrder(
        Price price,
        Quantity quantity,
        Side side,
        address user,
        TimeInForce timeInForce
    ) external returns (OrderId);

    function placeMarketOrder(
        Quantity quantity,
        Side side,
        address user
    ) external returns (OrderId);

    function cancelOrder(OrderId orderId, address user) external;

    function getOrderQueue(
        Side side,
        Price price
    ) external view returns (uint48 orderCount, uint256 totalVolume);

    function getBestPrice(Side side) external view returns (PriceVolume memory);

    function getUserActiveOrders(
        address user
    ) external view returns (Order[] memory);

    function getNextBestPrices(
        Side side,
        Price price,
        uint8 count
    ) external view returns (PriceVolume[] memory);

    function setTradingRules(TradingRules calldata tradingRules) external;

    function getTradingRules() external view returns (TradingRules memory);
}
