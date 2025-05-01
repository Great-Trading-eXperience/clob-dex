// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./Currency.sol";

struct PoolKey {
    Currency baseCurrency;
    Currency quoteCurrency;
}

type PoolId is bytes32;

library PoolIdLibrary {
    function toId(
        PoolKey memory poolKey
    ) internal pure returns (PoolId poolId) {
        assembly {
            poolId := keccak256(poolKey, 0x40)
        }
    }

    function baseToQuote(
        uint256 baseAmount,
        uint256 price,
        uint8 baseDecimals
    ) internal pure returns (uint256 quoteAmount) {
        quoteAmount = (baseAmount * price) / (10 ** baseDecimals);
        return quoteAmount;
    }

    function quoteToBase(
        uint256 quoteAmount,
        uint256 price,
        uint8 quoteDecimals
    ) internal pure returns (uint256 baseAmount) {
        baseAmount = (quoteAmount * (10 ** quoteDecimals)) / price;
        return baseAmount;
    }
}

using PoolIdLibrary for PoolKey global;
