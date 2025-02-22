// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @notice User-defined value type for order IDs
/// @dev Represents a unique identifier for orders using 48 bits
type OrderId is uint48;

/// @notice User-defined value type for order quantities
/// @dev Represents order quantities using 128 bits
type Quantity is uint128;

library QuantityLibrary {
    function decimals(Quantity /* price */ ) internal pure returns (uint8) {
        // Assuming the Price type is a fixed-point number with 8 decimal places
        return 18;
    }
}

using QuantityLibrary for Quantity global;

/// @notice Enum representing the side of an order
/// @dev BUY = 0, SELL = 1
enum Side {
    BUY,
    SELL
}

enum Status {
    OPEN,
    PARTIALLY_FILLED,
    FILLED,
    CANCELLED,
    EXPIRED
}

library SideLibrary {
    function opposite(Side side) internal pure returns (Side) {
        return side == Side.BUY ? Side.SELL : Side.BUY;
    }
}

using SideLibrary for Side global;
