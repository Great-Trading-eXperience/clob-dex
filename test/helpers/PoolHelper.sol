// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";

import {Currency} from "../../src/libraries/Currency.sol";
import {PoolKey} from "../../src/libraries/Pool.sol";

/**
 * @title PoolHelper
 * @dev Helper contract with utility functions for pool operations in tests
 */
contract PoolHelper {
    /**
     * @notice Gets a pool for the given currency pair
     * @param poolManager The pool manager to get the pool from
     * @param baseCurrency The base currency of the pair
     * @param quoteCurrency The quote currency of the pair
     * @return pool The pool for the currency pair
     */
    function _getPool(
        IPoolManager poolManager,
        Currency baseCurrency,
        Currency quoteCurrency
    ) internal view returns (IPoolManager.Pool memory pool) {
        PoolKey memory key = poolManager.createPoolKey(baseCurrency, quoteCurrency);
        return poolManager.getPool(key);
    }
}
