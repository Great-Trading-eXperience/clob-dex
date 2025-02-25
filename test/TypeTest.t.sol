// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/types/Pool.sol";
import "../src/types/Currency.sol";

contract TypeTest is Test {
    function testPoolKeyToIdSameInput() public pure {
        // Arrange
        Currency baseCurrency = Currency.wrap(address(0x1));
        Currency quoteCurrency = Currency.wrap(address(0x2));
        PoolKey memory poolKey1 = PoolKey(baseCurrency, quoteCurrency);
        PoolKey memory poolKey2 = PoolKey(baseCurrency, quoteCurrency);

        // Act
        PoolId id1 = poolKey1.toId();
        PoolId id2 = poolKey2.toId();

        // Assert
        assertEq(
            PoolId.unwrap(id1),
            PoolId.unwrap(id2),
            "PoolKey.toId() should result in the same ID for identical inputs"
        );
    }

    function testPoolKeyToIdDifferentInput() public pure {
        // Arrange
        Currency baseCurrency1 = Currency.wrap(address(0x1));
        Currency quoteCurrency1 = Currency.wrap(address(0x2));
        PoolKey memory poolKey1 = PoolKey(baseCurrency1, quoteCurrency1);

        Currency baseCurrency2 = Currency.wrap(address(0x3));
        Currency quoteCurrency2 = Currency.wrap(address(0x4));
        PoolKey memory poolKey2 = PoolKey(baseCurrency2, quoteCurrency2);

        // Act
        PoolId id1 = poolKey1.toId();
        PoolId id2 = poolKey2.toId();

        // Assert
        assertFalse(
            PoolId.unwrap(id1) == PoolId.unwrap(id2),
            "PoolKey.toId() should result in different IDs for different inputs"
        );
    }

    function testCurrencyEquality() public pure {
        // Arrange
        Currency currency1 = Currency.wrap(address(0x1));
        Currency currency2 = Currency.wrap(address(0x1));
        Currency currency3 = Currency.wrap(address(0x2));

        // Act & Assert
        assertTrue(currency1 == currency2, "Currencies with the same address should be equal");
        assertFalse(
            currency1 == currency3, "Currencies with different addresses should not be equal"
        );
    }

    function testCurrencyToIdAndFromId() public pure {
        // Arrange
        Currency currency = Currency.wrap(address(0x1));
        uint256 currencyId = currency.toId();

        // Act
        Currency convertedCurrency = CurrencyLibrary.fromId(currencyId);

        // Assert
        assertEq(
            Currency.unwrap(currency),
            Currency.unwrap(convertedCurrency),
            "Currency.fromId(Currency.toId()) should return the original Currency"
        );
    }
}
