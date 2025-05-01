// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../libraries/Currency.sol";
import {PoolKey} from "../libraries/Pool.sol";

/// @title GTXPoolManagerResolver - Resolver contract for the GTX Pool Manager
/// @notice Provides functions to resolve the pool address for a given base and quote currency
contract PoolManagerResolver {
    constructor() {}

    function getPool(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        address _poolManager
    ) public view returns (IPoolManager.Pool memory) {
        IPoolManager poolManager = IPoolManager(_poolManager);
        PoolKey memory key = poolManager.createPoolKey(_baseCurrency, _quoteCurrency);
        return poolManager.getPool(key);
    }

    function getPoolKey(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        address _poolManager
    ) public pure returns (PoolKey memory) {
        IPoolManager poolManager = IPoolManager(_poolManager);
        return poolManager.createPoolKey(_baseCurrency, _quoteCurrency);
    }
}
