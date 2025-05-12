// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

/**
 * @title GTXMarketMakerVaultStorage
 * Storage contract for GTXMarketMakerVault using ERC-7201 pattern
 */
abstract contract GTXMarketMakerVaultStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.marketmaker.storage.vault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x71b3c5a94f8e9cbe621386b798e08c315d24c2f78cd7a96fc93eae4509eba600;

    /// @custom:storage-location erc7201:gtx.marketmaker.storage.vault
    struct Storage {
        // Market maker parameters
        Currency baseCurrency;
        Currency quoteCurrency;
        uint256 targetRatio;        
        uint256 spread;             
        uint256 minSpread;          
        uint256 maxOrderSize;       
        uint256 slippageTolerance;  
        uint256 minActiveOrders;    
        
        // Infrastructure contracts
        address router;          
        address pool;              
        address balances;           
        address gauge;              
        
        // Trading state
        uint256 lastRebalance;      
        uint256 activeOrders;       
        
        // Constants
        uint256 rebalanceInterval;  
        
        // Gauge rewards tracking
        mapping(address => uint256) userRewards; 
    }

    function getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}