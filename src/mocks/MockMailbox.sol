// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockMailbox
 * @dev Mock Hyperlane mailbox for testing
 */
contract MockMailbox {
    event Dispatch(
        uint32 indexed destinationDomain,
        bytes32 indexed recipientAddress,
        bytes message
    );

    /**
     * @dev Mock dispatch function - just emits event
     */
    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external payable returns (bytes32) {
        emit Dispatch(destinationDomain, recipientAddress, messageBody);
        return keccak256(messageBody);
    }

    /**
     * @dev Mock quoteDispatch - returns 0 fee for testing
     */
    function quoteDispatch(
        uint32,
        bytes32,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
}
