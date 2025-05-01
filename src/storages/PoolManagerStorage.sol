// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../libraries/Currency.sol";
import {PoolId, PoolKey} from "../libraries/Pool.sol";

abstract contract PoolManagerStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.poolmanager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x3ba269338da0272c8c8ec2d2a5422e5b03f10c20a7fc80782a7f7c3e1b189600;

    /// @custom:storage-location erc7201:gtx.clob.storage.poolmanager
    struct Storage {
        address balanceManager;
        address router;
        address orderBookBeacon;
        mapping(PoolId => IPoolManager.Pool) pools;
        mapping(address => bool) registeredPools;
        mapping(Currency => bool) registeredCurrencies;
        Currency[] allCurrencies;
        Currency[] commonIntermediaries;
        mapping(Currency => bool) isCommonIntermediary;
        mapping(PoolId => uint256) poolLiquidity;
    }

    function getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}
