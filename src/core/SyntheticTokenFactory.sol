// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SyntheticTokenFactoryStorage} from "./storages/SyntheticTokenFactoryStorage.sol";
import {SyntheticToken} from "../token/SyntheticToken.sol";
import {TokenRegistry} from "./TokenRegistry.sol";

/**
 * @title SyntheticTokenFactory
 * @dev Factory contract for deploying and managing synthetic tokens for cross-chain assets
 * Integrates with TokenRegistry to maintain token mappings
 */
contract SyntheticTokenFactory is Initializable, OwnableUpgradeable, SyntheticTokenFactoryStorage {
    
    // Events
    event SyntheticTokenCreated(
        address indexed syntheticToken,
        uint32 indexed sourceChainId,
        address indexed sourceToken,
        string name,
        string symbol,
        uint8 decimals
    );
    event TokenRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event BridgeReceiverUpdated(address indexed oldReceiver, address indexed newReceiver);
    event TokenStatusChanged(address indexed syntheticToken, bool isActive);
    
    // Errors
    error TokenAlreadyExists(uint32 sourceChainId, address sourceToken);
    error TokenNotFound(address syntheticToken);
    error InvalidTokenRegistry();
    error InvalidBridgeReceiver();
    error InvalidSourceToken();
    error InvalidDecimals();
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(
        address _owner,
        address _tokenRegistry,
        address _bridgeReceiver
    ) public initializer {
        __Ownable_init(_owner);
        
        if (_tokenRegistry == address(0)) revert InvalidTokenRegistry();
        if (_bridgeReceiver == address(0)) revert InvalidBridgeReceiver();
        
        Storage storage $ = getStorage();
        $.tokenRegistry = TokenRegistry(_tokenRegistry);
        $.bridgeReceiver = _bridgeReceiver;
    }
    
    /**
     * @dev Create a new synthetic token for a cross-chain asset
     */
    function createSyntheticToken(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        string memory name,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) external onlyOwner returns (address syntheticToken) {
        return _createSyntheticToken(
            sourceChainId,
            sourceToken,
            targetChainId,
            name,
            symbol,
            sourceDecimals,
            syntheticDecimals
        );
    }
    
    /**
     * @dev Internal function to create a new synthetic token
     */
    function _createSyntheticToken(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        string memory name,
        string memory symbol,
        uint8 sourceDecimals,
        uint8 syntheticDecimals
    ) internal returns (address syntheticToken) {
        if (sourceToken == address(0)) revert InvalidSourceToken();
        if (syntheticDecimals == 0 || syntheticDecimals > 18) revert InvalidDecimals();
        
        Storage storage $ = getStorage();
        
        // Check if synthetic token already exists for this source token
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken);
        if ($.sourceToSynthetic[mappingKey] != address(0)) {
            revert TokenAlreadyExists(sourceChainId, sourceToken);
        }
        
        // Deploy new synthetic token with correct decimals
        syntheticToken = address(new SyntheticToken(name, symbol, syntheticDecimals, $.bridgeReceiver));
        
        // Store mappings
        $.sourceToSynthetic[mappingKey] = syntheticToken;
        $.syntheticToSource[syntheticToken] = SourceTokenInfo({
            sourceChainId: sourceChainId,
            sourceToken: sourceToken,
            sourceDecimals: sourceDecimals,
            syntheticDecimals: syntheticDecimals,
            isActive: true,
            createdAt: block.timestamp
        });
        
        // Add to enumeration
        $.allSyntheticTokens.push(syntheticToken);
        $.chainToSynthetics[sourceChainId].push(syntheticToken);
        
        // Note: TokenRegistry registration is now handled separately by the caller
        // This allows for better control over access permissions and deployment flow
        
        emit SyntheticTokenCreated(
            syntheticToken,
            sourceChainId,
            sourceToken,
            name,
            symbol,
            syntheticDecimals
        );
        
        return syntheticToken;
    }
    
    /**
     * @dev Batch create multiple synthetic tokens
     */
    function batchCreateSyntheticTokens(
        TokenCreationParams[] calldata params,
        uint32 targetChainId
    ) external onlyOwner returns (address[] memory syntheticTokens) {
        syntheticTokens = new address[](params.length);
        
        for (uint256 i = 0; i < params.length; i++) {
            syntheticTokens[i] = _createSyntheticToken(
                params[i].sourceChainId,
                params[i].sourceToken,
                targetChainId,
                params[i].name,
                params[i].symbol,
                params[i].sourceDecimals,
                params[i].syntheticDecimals
            );
        }
        
        return syntheticTokens;
    }
    
    /**
     * @dev Update the status of a synthetic token
     */
    function setSyntheticTokenStatus(
        address syntheticToken,
        bool isActive
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        SourceTokenInfo storage info = $.syntheticToSource[syntheticToken];
        if (info.sourceToken == address(0)) revert TokenNotFound(syntheticToken);
        
        info.isActive = isActive;
        
        emit TokenStatusChanged(syntheticToken, isActive);
    }
    
    /**
     * @dev Update the TokenRegistry address
     */
    function setTokenRegistry(address newTokenRegistry) external onlyOwner {
        if (newTokenRegistry == address(0)) revert InvalidTokenRegistry();
        
        Storage storage $ = getStorage();
        address oldRegistry = address($.tokenRegistry);
        $.tokenRegistry = TokenRegistry(newTokenRegistry);
        
        emit TokenRegistryUpdated(oldRegistry, newTokenRegistry);
    }
    
    /**
     * @dev Update the bridge receiver address
     */
    function setBridgeReceiver(address newBridgeReceiver) external onlyOwner {
        if (newBridgeReceiver == address(0)) revert InvalidBridgeReceiver();
        
        Storage storage $ = getStorage();
        address oldReceiver = $.bridgeReceiver;
        $.bridgeReceiver = newBridgeReceiver;
        
        emit BridgeReceiverUpdated(oldReceiver, newBridgeReceiver);
    }
    
    /**
     * @dev Update token mapping in TokenRegistry - for fixing decimal issues
     */
    function updateTokenMapping(
        uint32 sourceChainId,
        address sourceToken,
        uint32 targetChainId,
        address newSyntheticToken,
        uint8 newSyntheticDecimals
    ) external onlyOwner {
        Storage storage $ = getStorage();
        
        // Update the mapping in TokenRegistry
        $.tokenRegistry.updateTokenMapping(
            sourceChainId,
            sourceToken,
            targetChainId,
            newSyntheticToken,
            newSyntheticDecimals
        );
    }
    
    /**
     * @dev Get synthetic token address for a source token
     */
    function getSyntheticToken(
        uint32 sourceChainId,
        address sourceToken
    ) external view returns (address) {
        bytes32 mappingKey = _getMappingKey(sourceChainId, sourceToken);
        return getStorage().sourceToSynthetic[mappingKey];
    }
    
    /**
     * @dev Get source token information for a synthetic token
     */
    function getSourceTokenInfo(
        address syntheticToken
    ) external view returns (SourceTokenInfo memory) {
        return getStorage().syntheticToSource[syntheticToken];
    }
    
    /**
     * @dev Check if a synthetic token is active
     */
    function isSyntheticTokenActive(address syntheticToken) external view returns (bool) {
        return getStorage().syntheticToSource[syntheticToken].isActive;
    }
    
    /**
     * @dev Get all synthetic tokens
     */
    function getAllSyntheticTokens() external view returns (address[] memory) {
        return getStorage().allSyntheticTokens;
    }
    
    /**
     * @dev Get synthetic tokens for a specific source chain
     */
    function getChainSyntheticTokens(uint32 sourceChainId) external view returns (address[] memory) {
        return getStorage().chainToSynthetics[sourceChainId];
    }
    
    /**
     * @dev Get active synthetic tokens only
     */
    function getActiveSyntheticTokens() external view returns (address[] memory activeTokens) {
        Storage storage $ = getStorage();
        address[] memory allTokens = $.allSyntheticTokens;
        
        // Count active tokens first
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allTokens.length; i++) {
            if ($.syntheticToSource[allTokens[i]].isActive) {
                activeCount++;
            }
        }
        
        // Build active tokens array
        activeTokens = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allTokens.length; i++) {
            if ($.syntheticToSource[allTokens[i]].isActive) {
                activeTokens[index] = allTokens[i];
                index++;
            }
        }
        
        return activeTokens;
    }
    
    /**
     * @dev Convert amount between source and synthetic token decimals
     */
    function convertAmount(
        address syntheticToken,
        uint256 amount,
        bool sourceToSynthetic
    ) external view returns (uint256) {
        Storage storage $ = getStorage();
        SourceTokenInfo memory info = $.syntheticToSource[syntheticToken];
        
        if (info.sourceToken == address(0)) revert TokenNotFound(syntheticToken);
        
        if (sourceToSynthetic) {
            return _convertAmount(amount, info.sourceDecimals, info.syntheticDecimals);
        } else {
            return _convertAmount(amount, info.syntheticDecimals, info.sourceDecimals);
        }
    }
    
    /**
     * @dev Get current TokenRegistry address
     */
    function getTokenRegistry() external view returns (address) {
        return address(getStorage().tokenRegistry);
    }
    
    /**
     * @dev Get current bridge receiver address
     */
    function getBridgeReceiver() external view returns (address) {
        return getStorage().bridgeReceiver;
    }
    
    /**
     * @dev Get total number of synthetic tokens created
     */
    function getTotalSyntheticTokens() external view returns (uint256) {
        return getStorage().allSyntheticTokens.length;
    }
    
    /**
     * @dev Internal function to generate mapping key
     */
    function _getMappingKey(
        uint32 sourceChainId,
        address sourceToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(sourceChainId, sourceToken));
    }
    
    /**
     * @dev Internal function to convert amount between different decimal standards
     */
    function _convertAmount(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals > toDecimals) {
            return amount / (10 ** (fromDecimals - toDecimals));
        } else {
            return amount * (10 ** (toDecimals - fromDecimals));
        }
    }
}