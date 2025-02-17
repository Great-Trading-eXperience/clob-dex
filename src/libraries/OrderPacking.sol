// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Side} from "../types/Types.sol";
import {Price} from "./BokkyPooBahsRedBlackTreeLibrary.sol";

/// @title OrderPacking - A library for efficient order data packing
/// @notice Provides functions to pack and unpack order data into/from a single uint256
/// @dev Uses bit manipulation to pack side, price, and orderId into a single uint256
library OrderPacking {
    uint256 private constant SIDE_SHIFT = 144; // 256 - 64 - 48
    uint256 private constant PRICE_SHIFT = 48;
    uint256 private constant SIDE_MASK = 0x1 << SIDE_SHIFT;
    uint256 private constant PRICE_MASK = ((1 << 64) - 1) << PRICE_SHIFT;
    uint256 private constant ORDER_ID_MASK = (1 << 48) - 1;

    error InvalidPackedData();

    /// @notice Packs order data into a single uint256
    /// @param side The order side (BUY/SELL)
    /// @param price The order price
    /// @param orderId The order ID
    /// @return packed The packed order data
    function packOrder(Side side, Price price, uint48 orderId) internal pure returns (uint256) {
        if (orderId == 0) revert InvalidPackedData();

        return (uint256(side) << SIDE_SHIFT) | (uint256(Price.unwrap(price)) << PRICE_SHIFT) | uint256(orderId);
    }

    /// @notice Unpacks order data from a single uint256
    /// @param packed The packed order data
    /// @return side The order side
    /// @return price The order price
    /// @return orderId The order ID
    function unpackOrder(uint256 packed) internal pure returns (Side side, Price price, uint48 orderId) {
        side = Side((packed & SIDE_MASK) >> SIDE_SHIFT);
        price = Price.wrap(uint64((packed & PRICE_MASK) >> PRICE_SHIFT));
        orderId = uint48(packed & ORDER_ID_MASK);

        if (orderId == 0) revert InvalidPackedData();
    }
}
