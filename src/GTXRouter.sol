// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side} from "./types/Types.sol";
import {Currency} from "./types/Currency.sol";
import {PoolKey} from "./types/Pool.sol";
import {Price} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

/// @title GTXRouter - A router for interacting with the OrderBook
/// @notice Provides functions to place and cancel orders
contract GTXRouter {
    IPoolManager public poolManager;
    IBalanceManager public balanceManager;

    constructor(address _poolManager, address _balanceManager) {
        poolManager = IPoolManager(_poolManager);
        balanceManager = IBalanceManager(_balanceManager);
    }

    function placeOrder(PoolKey calldata key, Price price, Quantity quantity, Side side)
        public
        returns (OrderId orderId)
    {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderId = pool.orderBook.placeOrder(price, quantity, side, msg.sender);
    }

    function placeOrderWithDeposit(PoolKey calldata key, Price price, Quantity quantity, Side side)
        external
        returns (OrderId orderId)
    {
        (Currency currency, uint256 amount) = key.calculateAmountAndCurrency(price, quantity, side);
        IBalanceManager(balanceManager).deposit(currency, amount, msg.sender);
        orderId = placeOrder(key, price, quantity, side);
    }

    function placeMarketOrder(PoolKey calldata key, Quantity quantity, Side side) public returns (OrderId orderId) {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderId = pool.orderBook.placeMarketOrder(quantity, side, msg.sender);
    }

    function placeMarketOrderWithDeposit(PoolKey calldata key, Price price, Quantity quantity, Side side)
        external
        returns (OrderId orderId)
    {
        (Currency currency, uint256 amount) = key.calculateAmountAndCurrency(price, quantity, side);
        IBalanceManager(balanceManager).deposit(currency, amount, msg.sender);
        orderId = placeMarketOrder(key, quantity, side);
    }

    function cancelOrder(PoolKey calldata key, Side side, Price price, OrderId orderId) external {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        pool.orderBook.cancelOrder(side, price, orderId, msg.sender);
    }

    function getBestPrice(PoolKey calldata key, Side side) external view returns (IOrderBook.PriceVolume memory) {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getBestPrice(side);
    }

    function getOrderQueue(PoolKey calldata key, Side side, Price price)
        external
        view
        returns (uint48 orderCount, uint256 totalVolume)
    {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getOrderQueue(side, price);
    }

    function getUserActiveOrders(PoolKey calldata key, address user)
        external
        view
        returns (IOrderBook.Order[] memory)
    {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getUserActiveOrders(user);
    }

    function getNextBestPrices(PoolKey calldata key, Side side, Price price, uint8 count)
        external
        view
        returns (IOrderBook.PriceVolume[] memory)
    {
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        return pool.orderBook.getNextBestPrices(side, price, count);
    }
}
