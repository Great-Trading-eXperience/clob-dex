// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract ChainBalanceManagerStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.clob.storage.chainbalancemanager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = bytes32(uint256(keccak256("gtx.clob.storage.chainbalancemanager")) - 1);

    struct Storage {
        // User balances: user => token => amount (locked in vault)
        mapping(address => mapping(address => uint256)) balanceOf;
        
        // Unlocked balances ready for withdrawal: user => token => amount
        mapping(address => mapping(address => uint256)) unlockedBalanceOf;
        
        // Whitelisted tokens
        mapping(address => bool) whitelistedTokens;
        address[] tokenList;
        
        // Cross-chain token mappings (following Espresso pattern)
        mapping(address => address) sourceToSynthetic;  // sourceToken => syntheticToken address on Rari
        mapping(address => address) syntheticToSource;  // syntheticToken => sourceToken (reverse lookup)
        
        // Unified messaging configuration
        address messageHandler;              // Either mailbox (cross-chain) OR balanceManager (same-chain)
        uint32 localDomain;
        uint32 destinationDomain;           // Rari testnet domain
        address destinationBalanceManager;  // BalanceManager on Rari
        bool isDestinationChain;            // NEW: true if this is on destination chain (Rari)
        
        // Legacy mailbox field for backward compatibility
        address mailbox;
        
        // Security - User nonces for replay protection (Espresso pattern)
        mapping(address => uint256) userNonces;
        
        // Security - Processed messages to prevent replay attacks
        mapping(bytes32 => bool) processedMessages;
        
        // Additional accounting
        mapping(address => uint256) totalDeposited;      // Total deposited per token
        mapping(address => uint256) totalWithdrawn;      // Total withdrawn per token
        mapping(address => uint256) totalUnlocked;       // Total unlocked per token

        // Vault integration
        address vaultFactory;                            // VaultFactory contract address
        mapping(address => address) tokenVaults;         // token => vault address
        mapping(address => uint256) vaultAllocationBps;  // token => allocation in basis points (e.g., 8000 = 80%)
        uint256 defaultKeepBps;                          // Default % to keep (e.g., 2000 = 20%)
        uint256 defaultVaultBps;                         // Default % to vault (e.g., 8000 = 80%)
    }

    function getStorage() internal pure returns (Storage storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}