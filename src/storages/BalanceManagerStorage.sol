// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract BalanceManagerStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.balancemanager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0xa0938c47b5c654ca88fd5f46a35251d66e96b0e70f06871f4be1ef4fd259f100;

    struct Storage {
        mapping(address => mapping(uint256 => uint256)) balanceOf;
        mapping(address => mapping(address => mapping(uint256 => uint256))) lockedBalanceOf;
        mapping(address => bool) authorizedOperators;
        address poolManager;
        address feeReceiver;
        uint256 feeMaker;
        uint256 feeTaker;
        uint256 feeUnit;
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
