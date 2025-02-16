// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderId, Quantity, Side, Status} from "../types/Types.sol";

interface IOrderBook {
    struct Order {
        OrderId id;
        address user;
        OrderId next;
        OrderId prev;
        uint48 timestamp;
        uint48 expiry;
        Price price;
        Status status;
        Quantity quantity;
        Quantity filled;
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

    function placeOrder(
        Price price,
        Quantity quantity,
        Side side
    ) external returns (OrderId);

    function placeMarketOrder(
        Quantity quantity,
        Side side
    ) external returns (OrderId);

    function cancelOrder(Side side, Price price, OrderId orderId) external;

    function getUserActiveOrders(
        address user
    ) external view returns (Order[] memory);

    function getBestPrice(Side side) external view returns (PriceVolume memory);

    function getNextBestPrices(
        Side side,
        Price price,
        uint8 count
    ) external view returns (PriceVolume[] memory);
}
