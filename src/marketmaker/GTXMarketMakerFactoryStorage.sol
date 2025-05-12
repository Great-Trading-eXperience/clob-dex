// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

/**
 * @title GTXMarketMakerFactoryStorage
 * Storage contract for GTXMarketMakerFactory using ERC-7201 pattern
 */
abstract contract GTXMarketMakerFactoryStorage {
    // keccak256(abi.encode(uint256(keccak256("gtx.marketmaker.storage.factory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x65c6a3b02710adc7a96a66f7a0c71f51e366563c0e905286c0dbc4e08e14a500;

    /// @custom:storage-location erc7201:gtx.marketmaker.storage.factory
    struct Storage {
        // Vault registry
        mapping(address => bool) isVault;
        
        // Infrastructure addresses
        address veToken;
        address gaugeController;
        address router;
        address poolManager;
        address balanceManager;
        
        // Beacon for vault upgrades
        address vaultBeacon;
        address vaultImplementation;
        
        // Parameter constraints
        uint256 minTargetRatio;       
        uint256 maxTargetRatio;       
        uint256 minSpread;            
        uint256 maxSpread;            
        uint256 minOrderSize;         
        uint256 maxOrderSize;         
        uint256 minSlippageTolerance; 
        uint256 maxSlippageTolerance; 
        uint256 minActiveOrders;      
        uint256 maxActiveOrders;      
        uint256 minRebalanceInterval; 
        uint256 maxRebalanceInterval; 
    }

    function getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }
}