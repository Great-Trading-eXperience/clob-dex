// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract TokenRegistryStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.tokenregistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x7b3f8e9c2d1a5b7e9f3c5a8d1f4b7e0c3a6d9e2f5b8e1c4a7d0f3b6c9e2d5a00;

    struct TokenMapping {
        uint32 sourceChainId;        // Chain ID of the source token
        address sourceToken;         // Address of the source token
        uint32 targetChainId;        // Chain ID where synthetic token exists
        address syntheticToken;      // Address of the synthetic token
        string symbol;               // Symbol of the synthetic token (e.g., "gsUSDC")
        uint8 sourceDecimals;        // Decimals of the source token
        uint8 syntheticDecimals;     // Decimals of the synthetic token
        bool isActive;               // Whether this mapping is active
        uint256 registeredAt;        // Timestamp when mapping was registered
    }

    struct ReverseMapping {
        uint32 sourceChainId;        // Original chain ID
        address sourceToken;         // Original token address
    }

    struct Storage {
        // EXISTING STORAGE - DO NOT CHANGE ORDER TO PRESERVE DATA
        // Main mappings: keccak256(sourceChainId, sourceToken, targetChainId) => TokenMapping
        mapping(bytes32 => TokenMapping) tokenMappings;
        
        // Reverse mappings: keccak256(targetChainId, syntheticToken) => ReverseMapping
        mapping(bytes32 => ReverseMapping) reverseMappings;
        
        // Chain to tokens enumeration: chainId => sourceToken[]
        mapping(uint32 => address[]) chainToTokens;
        
        // NEW STORAGE - ADDED AT END TO PRESERVE LAYOUT
        address factory;             // SyntheticTokenFactory address for factory-only operations
        bool upgradeInitialized;     // Flag to track upgrade initialization
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}