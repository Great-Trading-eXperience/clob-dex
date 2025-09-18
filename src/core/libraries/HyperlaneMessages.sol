// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title HyperlaneMessages
 * @dev Espresso testnet proven message structures for cross-chain communication
 * Based on the working patterns from espresso-hyperlane-example
 */
library HyperlaneMessages {
    // Message type constants (logical flow order)
    uint8 constant DEPOSIT_MESSAGE = 1;     // Source Chain → Rari (lock → mint)
    uint8 constant WITHDRAW_MESSAGE = 2;    // Rari → Source Chain (burn → unlock)

    /**
     * @dev Withdrawal message: sent from Rari to source chain
     * Flow: BalanceManager.requestWithdraw() → ChainBalanceManager.handle()
     */
    struct WithdrawMessage {
        uint8 messageType;       // WITHDRAW_MESSAGE = 2
        address syntheticToken;  // gsUSDC, gsWETH, etc. (Rari address)
        address recipient;       // User address on destination chain
        uint256 amount;          // Amount to unlock
        uint32 targetChainId;    // Destination chain domain ID
        uint256 nonce;           // User nonce for replay protection
    }

    /**
     * @dev Deposit message: sent from source chain to Rari  
     * Flow: ChainBalanceManager.bridgeToSynthetic() → BalanceManager.handle()
     */
    struct DepositMessage {
        uint8 messageType;       // DEPOSIT_MESSAGE = 1
        address syntheticToken;  // gsUSDC, gsWETH, etc. (Rari address)
        address user;            // User address (same across all chains)
        uint256 amount;          // Amount deposited
        uint32 sourceChainId;    // Source chain domain ID
        uint256 nonce;           // User nonce for replay protection
    }


    /**
     * @dev Enhanced message with additional metadata for advanced use cases
     */
    struct CrossChainMessage {
        uint8 messageType;
        address token;
        address user;
        uint256 amount;
        uint32 chainId;
        uint256 nonce;
        bytes32 messageId;       // Unique identifier
        uint256 timestamp;       // Block timestamp
        bytes extraData;         // Additional data for future extensions
    }

    /**
     * @dev Generate unique message ID for replay protection
     */
    function generateMessageId(
        uint32 origin,
        bytes32 sender,
        bytes calldata messageBody
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(origin, sender, messageBody));
    }

    /**
     * @dev Encode deposit message for cross-chain sending
     */
    function encodeDepositMessage(
        address syntheticToken,
        address user,
        uint256 amount,
        uint32 sourceChainId,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        DepositMessage memory message = DepositMessage({
            messageType: DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: user,
            amount: amount,
            sourceChainId: sourceChainId,
            nonce: nonce
        });
        return abi.encode(message);
    }

    /**
     * @dev Encode withdrawal message for cross-chain sending
     */
    function encodeWithdrawMessage(
        address syntheticToken,
        address recipient,
        uint256 amount,
        uint32 targetChainId,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        WithdrawMessage memory message = WithdrawMessage({
            messageType: WITHDRAW_MESSAGE,
            syntheticToken: syntheticToken,
            recipient: recipient,
            amount: amount,
            targetChainId: targetChainId,
            nonce: nonce
        });
        return abi.encode(message);
    }

    /**
     * @dev Decode incoming message and determine type
     */
    function decodeMessageType(bytes calldata messageBody) internal pure returns (uint8) {
        return abi.decode(messageBody, (uint8));
    }

    /**
     * @dev Decode deposit message
     */
    function decodeDepositMessage(bytes calldata messageBody) 
        internal pure returns (DepositMessage memory) {
        return abi.decode(messageBody, (DepositMessage));
    }

    /**
     * @dev Decode withdrawal message
     */
    function decodeWithdrawMessage(bytes calldata messageBody) 
        internal pure returns (WithdrawMessage memory) {
        return abi.decode(messageBody, (WithdrawMessage));
    }
}