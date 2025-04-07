// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey, PoolId} from "../types/Pool.sol";
import {Currency} from "../types/Currency.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderId, Quantity, Side} from "../types/Types.sol";

interface IPoolManager {
    error InvalidRouter();

    struct Pool {
        Currency baseCurrency;
        Currency quoteCurrency;
        IOrderBook orderBook;
    }

    event PoolCreated(
        PoolId indexed poolId, address orderBook, Currency baseCurrency, Currency quoteCurrency
    );

    function setRouter(
        address router
    ) external;

    function getPool(
        PoolKey calldata key
    ) external view returns (Pool memory);

    function getPoolId(
        PoolKey calldata key
    ) external pure returns (PoolId);

    function createPool(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.TradingRules memory _tradingRules
    ) external returns (PoolId);

    /**
     * @notice Adds a currency to the list of common intermediaries (preferred for routing)
     * @param currency The currency to add
     */
    function addCommonIntermediary(
        Currency currency
    ) external;

    /**
     * @notice Removes a currency from the list of common intermediaries
     * @param currency The currency to remove
     */
    function removeCommonIntermediary(
        Currency currency
    ) external;

    /**
     * @notice Updates the liquidity score for a pool (affects routing priority)
     * @param key The pool key
     * @param liquidityScore The new liquidity score (higher means more priority in routing)
     */
    function updatePoolLiquidity(PoolKey calldata key, uint256 liquidityScore) external;

    /**
     * @notice Get all registered currencies that have at least one pool
     * @return currencies Array of all currencies in the system
     */
    function getAllCurrencies() external view returns (Currency[] memory);

    /**
     * @notice Get common intermediary currencies (preferred for routing)
     * @return intermediaries Array of common intermediary currencies
     */
    function getCommonIntermediaries() external view returns (Currency[] memory);

    /**
     * @notice Check if a pool exists between two currencies
     * @param currency1 First currency
     * @param currency2 Second currency
     * @return exists Whether a pool exists
     */
    function poolExists(Currency currency1, Currency currency2) external view returns (bool);

    /**
     * @notice Get the liquidity score for a pool
     * @param currency1 First currency
     * @param currency2 Second currency
     * @return score The liquidity score (0 if pool doesn't exist)
     */
    function getPoolLiquidityScore(
        Currency currency1,
        Currency currency2
    ) external view returns (uint256);

    /**
     * @notice Create a pool key with the correct order of currencies
     */
    function createPoolKey(
        Currency currency1,
        Currency currency2
    ) external pure returns (PoolKey memory);
}
