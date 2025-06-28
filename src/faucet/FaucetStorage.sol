// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

abstract contract FaucetStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.faucet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x8d9f887b4b13c86d46e0fe9c8f0c1f8f6d5e0c8a7b4e1d2c5b8a3f6e9d2c5f00;

    struct Storage {
        address owner;
        address[] availableTokens;
        uint256 faucetAmount;
        uint256 faucetCooldown;
        mapping(address => uint256) lastRequestTime;
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}