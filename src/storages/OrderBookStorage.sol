// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {PoolKey} from "../libraries/Pool.sol";
import {RedBlackTreeLib} from "@solady/utils/RedBlackTreeLib.sol";

abstract contract OrderBookStorage {
    using RedBlackTreeLib for RedBlackTreeLib.Tree;

    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.orderbook")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0xde8fa57b24aed10e6adb2761ee28c13cc4ef93295c71b37f8f995a47d263b500;

    /// @custom:storage-location erc7201:gtx.clob.storage.orderbook
    struct Storage {
        address balanceManager;
        address router;
        uint48 nextOrderId;
        uint48 expiryDays;
        PoolKey poolKey;
        IOrderBook.TradingRules tradingRules;
        mapping(IOrderBook.Side => RedBlackTreeLib.Tree) priceTrees;
        mapping(uint48 => IOrderBook.Order) orders;
        mapping(IOrderBook.Side => mapping(uint128 => IOrderBook.OrderQueue)) orderQueues;
    }

    function getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
