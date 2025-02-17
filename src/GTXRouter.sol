// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
// import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {PoolManager} from "./PoolManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side} from "./types/Types.sol";
import {Currency} from "./types/Currency.sol";
import {PoolKey} from "./types/Pool.sol";
import {Price} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

/// @title GTXRouter - A router for interacting with the OrderBook
/// @notice Provides functions to place and cancel orders
contract GTXRouter {
    PoolManager public poolManager;

    // / @notice Initializes the router with the given order book
    // / @param _orderBook The address of the order book contract
    constructor(PoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @notice Places a limit order through the order book
    function placeOrder(PoolKey calldata key, Price price, Quantity quantity, Side side) external returns (OrderId) {
        // address user = msg.sender;
        // Additional logic to place the order would go here
        // poolManager.deposit(token, amount);
    }

    function placeMarketOrder(Quantity quantity, Side side) external returns (OrderId) {
        // address user = msg.sender;
        // Additional logic to place the market order would go here
    }

    function deposit(Currency currency, Quantity quantity) public {}
}
