// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract GTXRouterStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.router")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x9ec3368d5a8fe109d38c1c97062a434aceba59808a6867d2e2f01bef07493400;

    struct Storage {
        address poolManager;
        address balanceManager;
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}
