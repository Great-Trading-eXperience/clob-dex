// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

type Currency is address;

using {greaterThan as >, lessThan as <, greaterThanOrEqualTo as >=, equals as ==} for Currency global;
using CurrencyLibrary for Currency global;

function equals(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) == Currency.unwrap(other);
}

function greaterThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) > Currency.unwrap(other);
}

function lessThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) < Currency.unwrap(other);
}

function greaterThanOrEqualTo(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) >= Currency.unwrap(other);
}

/// @title CurrencyLibrary
/// @dev This library allows for transferring and holding native tokens and ERC20 tokens

/// @title CurrencyLibrary
/// @dev Library for transferring native tokens and ERC20 tokens using SafeTransferLib
library CurrencyLibrary {
    error NativeTransferFailed();
    error ERC20TransferFailed();

    Currency public constant ADDRESS_ZERO = Currency.wrap(address(0));

    function transfer(Currency currency, address to, uint256 amount) internal {
        if (isAddressZero(currency)) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(Currency.unwrap(currency), to, amount);
        }
    }

    function transferFrom(Currency currency, address from, address to, uint256 amount) internal {
        if (isAddressZero(currency)) {
            revert NativeTransferFailed();
        } else {
            SafeTransferLib.safeTransferFrom(Currency.unwrap(currency), from, to, amount);
        }
    }

    function balanceOfSelf(
        Currency currency
    ) internal view returns (uint256) {
        if (isAddressZero(currency)) {
            return address(this).balance;
        } else {
            return IERC20(Currency.unwrap(currency)).balanceOf(address(this));
        }
    }

    function balanceOf(Currency currency, address owner) internal view returns (uint256) {
        if (isAddressZero(currency)) {
            return owner.balance;
        } else {
            return IERC20(Currency.unwrap(currency)).balanceOf(owner);
        }
    }

    function isAddressZero(
        Currency currency
    ) internal pure returns (bool) {
        return Currency.unwrap(currency) == Currency.unwrap(ADDRESS_ZERO);
    }

    function toId(
        Currency currency
    ) internal pure returns (uint256) {
        return uint160(Currency.unwrap(currency));
    }

    // fromId and decimals functions remain unchanged
    function fromId(
        uint256 id
    ) internal pure returns (Currency) {
        return Currency.wrap(address(uint160(id)));
    }

    function decimals(
        Currency currency
    ) internal view returns (uint8) {
        return IERC20(Currency.unwrap(currency)).decimals();
    }
}
