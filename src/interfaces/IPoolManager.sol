// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey, PoolId} from "../types/Pool.sol";
import {Currency} from "../types/Currency.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderId, Quantity, Side} from "../types/Types.sol";

interface IPoolManager {
    error InvalidRouter();
    error InvalidBaseVault(PoolKey key, address baseVault);
    error InvalidQuoteVault(PoolKey key, address quoteVault);

    struct Pool {
        uint256 maxOrderAmount;
        uint256 lotSize;
        Currency baseCurrency;
        Currency quoteCurrency;
        address baseVault;
        address quoteVault;
        IOrderBook orderBook;
    }

    event PoolCreated(
        PoolId indexed id,
        address indexed orderBook,
        Currency baseCurrency,
        Currency quoteCurrency,
        address baseVault,
        address quoteVault,
        uint256 lotSize,
        uint256 maxOrderAmount
    );

    function setRouter(address router) external;

    function getPool(PoolKey calldata key) external view returns (Pool memory);

    function getPoolId(PoolKey calldata key) external pure returns (PoolId);

    function createPool(
        PoolKey calldata key,
        address baseVault,
        address quoteVault,
        uint256 _lotSize,
        uint256 _maxOrderAmount
    ) external returns (address);
}
