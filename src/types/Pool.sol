// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./Currency.sol";
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {Quantity, Side} from "./Types.sol";

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

    function calculateAmountsAndCurrencies(
        PoolKey memory poolKey,
        Price price,
        Quantity quantity,
        Side side
    )
        internal
        view
        returns (Currency currency0, uint256 amount0, Currency currency1, uint256 amount1)
    {
        uint8 baseCurrencyDecimals = poolKey.baseCurrency.decimals();
        uint8 quoteCurrencyDecimals = poolKey.quoteCurrency.decimals();
        uint8 priceDecimals = price.decimals();
        uint8 quantityDecimals = quantity.decimals();

        uint256 rawPrice = uint256(Price.unwrap(price));
        uint256 rawQuantity = uint256(Quantity.unwrap(quantity));

        if (side == Side.BUY) {
            // BUY side logic
            currency0 = poolKey.quoteCurrency; // buyCurrency
            uint256 buyAdjustmentFactor =
                10 ** (priceDecimals + quantityDecimals - quoteCurrencyDecimals);
            amount0 = (rawPrice * rawQuantity) / buyAdjustmentFactor;

            currency1 = poolKey.baseCurrency; // sellCurrency
            uint256 sellAdjustmentFactor = 10 ** (quantityDecimals - baseCurrencyDecimals);
            amount1 = rawQuantity / sellAdjustmentFactor;
        } else {
            // SELL side logic
            currency0 = poolKey.baseCurrency; // sellCurrency
            uint256 sellAdjustmentFactor = 10 ** (quantityDecimals - baseCurrencyDecimals);
            amount0 = rawQuantity / sellAdjustmentFactor;

            currency1 = poolKey.quoteCurrency; // buyCurrency
            uint256 buyAdjustmentFactor =
                10 ** (priceDecimals + quantityDecimals - quoteCurrencyDecimals);
            amount1 = (rawPrice * rawQuantity) / buyAdjustmentFactor;
        }
    }

    function calculateAmountAndCurrency(
        PoolKey memory poolKey,
        Price price,
        Quantity quantity,
        Side side
    ) internal view returns (Currency currency, uint256 amount) {
        uint8 baseCurrencyDecimals = poolKey.baseCurrency.decimals();
        uint8 quoteCurrencyDecimals = poolKey.quoteCurrency.decimals();
        uint8 priceDecimals = price.decimals();
        uint8 quantityDecimals = quantity.decimals();

        uint256 rawPrice = uint256(Price.unwrap(price));
        uint256 rawQuantity = uint256(Quantity.unwrap(quantity));

        if (side == Side.BUY) {
            // Calculate for BUY side
            currency = poolKey.quoteCurrency;
            uint256 buyAdjustmentFactor =
                10 ** (priceDecimals + quantityDecimals - quoteCurrencyDecimals);
            amount = (rawPrice * rawQuantity) / buyAdjustmentFactor;
        } else {
            // Calculate for SELL side
            currency = poolKey.baseCurrency;
            uint256 sellAdjustmentFactor = 10 ** (quantityDecimals - baseCurrencyDecimals);
            amount = rawQuantity / sellAdjustmentFactor;
        }
    }
}

using PoolIdLibrary for PoolKey global;
