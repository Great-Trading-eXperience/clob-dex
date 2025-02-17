// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./Currency.sol";

struct PoolKey {
    Currency baseCurrency;
    Currency quoteCurrency;
}

type PoolId is bytes32;

/// @notice Library for computing the ID of a pool
library PoolIdLibrary {
    /// @notice Returns value equal to keccak256(abi.encode(poolKey))
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly ("memory-safe") {
            // 0xa0 represents the total size of the poolKey struct (5 slots of 32 bytes)
            poolId := keccak256(poolKey, 0xa0)
        }
    }
}

using PoolIdLibrary for PoolKey global;

struct PoolOrderBook {
    address poolManager;
    PoolKey poolKey;
}
