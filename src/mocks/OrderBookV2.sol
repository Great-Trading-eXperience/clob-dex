// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../OrderBook.sol";

/// @custom:oz-upgrades-from OrderBook
contract OrderBookV2 is OrderBook {
    function getVersion() external pure returns (string memory) {
        return "OrderBook V2";
    }
}
