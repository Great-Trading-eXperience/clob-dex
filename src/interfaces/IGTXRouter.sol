// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";
import {PoolKey} from "../libraries/Pool.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {IPoolManager} from "./IPoolManager.sol";

interface IGTXRouter {
    function placeOrder(
        IPoolManager.Pool memory pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        address _user
    ) external returns (uint48 orderId);

    function placeOrderWithDeposit(
        IPoolManager.Pool memory pool,
        uint128 _price,
        uint128 _quantity,
        IOrderBook.Side _side,
        address _user
    ) external returns (uint48 orderId);

    function placeMarketOrder(
        IPoolManager.Pool memory pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        address _user
    ) external returns (uint48 orderId);

    function placeMarketOrderWithDeposit(
        IPoolManager.Pool memory pool,
        uint128 _quantity,
        IOrderBook.Side _side,
        address _user
    ) external returns (uint48 orderId);

    function cancelOrder(IPoolManager.Pool memory pool, uint48 orderId) external;

    function getBestPrice(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side
    ) external view returns (IOrderBook.PriceVolume memory);

    function getOrderQueue(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.Side side,
        uint128 price
    ) external view returns (uint48 orderCount, uint256 totalVolume);

    function getOrder(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        uint48 orderId
    ) external view returns (IOrderBook.Order memory);

    function getNextBestPrices(
        IPoolManager.Pool memory pool,
        IOrderBook.Side side,
        uint128 price,
        uint8 count
    ) external view returns (IOrderBook.PriceVolume[] memory);
}
