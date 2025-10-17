// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IChainBalanceManagerErrors {
    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error InsufficientUnlockedBalance(address user, uint256 id, uint256 want, uint256 have);
    error ZeroAmount();
    error ZeroAddress();
    error UnauthorizedWithdraw(address caller);
    error TokenNotWhitelisted(address token);
    error TokenAlreadyWhitelisted(address token);
    error TokenNotFound(address token);
    
    // Hyperlane cross-chain errors (Espresso pattern)
    error OnlyMailbox();
    error InvalidOrigin(uint32 origin);
    error InvalidSender(bytes32 sender);
    error InvalidMessageType(uint8 messageType);
    error MessageAlreadyProcessed(bytes32 messageId);
    error TokenMappingNotFound(address token);
    error InvalidSyntheticToken(address syntheticToken);

    // Vault-related errors
    error VaultNotFound(address token);
    error VaultAlreadyExists(address token);
    error InvalidAllocation(uint256 keepBps, uint256 vaultBps);
    error InvalidChainConfiguration();
}