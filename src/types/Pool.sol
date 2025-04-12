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

/// @notice Library for computing the ID of a pool and handling currency conversions
library PoolIdLibrary {
    /// @notice Returns value equal to keccak256(abi.encode(poolKey))
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
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

    /// @notice Calculate amounts and currencies for both sides of a trade
    function calculateAmountsAndCurrencies(
        PoolKey memory poolKey,
        Price price,
        Quantity quantity,
        Side side
    ) internal view returns (
        Currency currency0,
        uint256 amount0,
        Currency currency1,
        uint256 amount1
    ) {
        uint8 baseDecimals = poolKey.baseCurrency.decimals();
        uint8 quoteDecimals = poolKey.quoteCurrency.decimals();
        uint8 priceDecimals = price.decimals();
        uint256 rawPrice = uint256(Price.unwrap(price));
        uint256 rawQuantity = uint256(Quantity.unwrap(quantity));

        // For quote amount (USDC), we need to:
        // 1. Multiply quantity (e.g., 1e18 ETH) by price (e.g., 2000e8)
        // 2. Adjust decimals to match quote currency (e.g., USDC 6 decimals)
        uint256 quoteAmount;
        {
            require(rawQuantity <= type(uint256).max / rawPrice, "Multiply overflow");
            uint256 rawQuoteAmount = rawQuantity * rawPrice;
            
            // Adjust to quote currency decimals
            // e.g., (1e18 * 2000e8) / 1e20 = 2000e6 (USDC)
            uint256 adjustmentFactor = 10 ** (baseDecimals + priceDecimals - quoteDecimals);
            quoteAmount = rawQuoteAmount / adjustmentFactor;
        }

        // For base amount (ETH), we just need to ensure it's in base currency decimals
        uint256 baseAmount = rawQuantity;

        if (side == Side.BUY) {
            currency0 = poolKey.quoteCurrency; // buyCurrency (e.g., USDC)
            amount0 = quoteAmount;
            currency1 = poolKey.baseCurrency; // sellCurrency (e.g., ETH)
            amount1 = baseAmount;
        } else {
            currency0 = poolKey.baseCurrency; // sellCurrency (e.g., ETH)
            amount0 = baseAmount;
            currency1 = poolKey.quoteCurrency; // buyCurrency (e.g., USDC)
            amount1 = quoteAmount;
        }
    }

    function convertCurrency(
        PoolKey memory poolKey,
        Price price,
        Quantity quantity,
        bool baseToQuote
    ) internal view returns (uint128 amount) {
        uint8 baseDecimals = poolKey.baseCurrency.decimals();
        uint8 quoteDecimals = poolKey.quoteCurrency.decimals();
        uint8 priceDecimals = price.decimals();
        uint256 rawPrice = uint256(Price.unwrap(price));
        uint256 rawQuantity = uint256(Quantity.unwrap(quantity));

        int8 exponent = baseToQuote
            ? int8(quoteDecimals) - int8(baseDecimals) - int8(priceDecimals)
            : int8(baseDecimals) + int8(priceDecimals) - int8(quoteDecimals);

        uint256 result;
        if (baseToQuote) {
            uint256 product = rawQuantity * rawPrice;
            result = exponent >= 0
                ? product * (10 ** uint8(exponent))
                : product / (10 ** uint8(-exponent));
        } else {
            result = exponent >= 0
                ? (rawQuantity * (10 ** uint8(exponent))) / rawPrice
                : (rawQuantity / rawPrice) / (10 ** uint8(-exponent));
        }

        return uint128(result);
    }
}

using PoolIdLibrary for PoolKey global;