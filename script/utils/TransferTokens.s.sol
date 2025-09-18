// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DeployHelpers.s.sol";

/**
 * @title Transfer Tokens
 * @dev Transfer tokens from primary account to secondary account for testing
 * 
 * Usage:
 *   RECIPIENT=0x... TOKEN_SYMBOL=USDC AMOUNT=1000000000 forge script script/utils/TransferTokens.s.sol --broadcast
 */
contract TransferTokens is DeployHelpers {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        loadDeployments();
        
        // Get parameters
        address recipient = vm.envAddress("RECIPIENT");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint256 amount = vm.envUint("AMOUNT");
        
        console.log("=== TRANSFERRING TOKENS ===");
        console.log("From:", vm.addr(deployerPrivateKey));
        console.log("To:", recipient);
        console.log("Token:", tokenSymbol);
        console.log("Amount:", amount);
        
        // Get token address
        require(deployed[tokenSymbol].isSet, string.concat("Token ", tokenSymbol, " not found"));
        address tokenAddress = deployed[tokenSymbol].addr;
        IERC20 token = IERC20(tokenAddress);
        
        console.log("Token address:", tokenAddress);
        
        // Check balances
        uint256 senderBalance = token.balanceOf(vm.addr(deployerPrivateKey));
        uint256 recipientBalance = token.balanceOf(recipient);
        
        console.log("Sender balance before:", senderBalance);
        console.log("Recipient balance before:", recipientBalance);
        
        require(senderBalance >= amount, "Insufficient balance for transfer");
        
        // Transfer tokens
        bool success = token.transfer(recipient, amount);
        require(success, "Transfer failed");
        
        console.log("Transfer successful!");
        
        // Check final balances
        uint256 finalSenderBalance = token.balanceOf(vm.addr(deployerPrivateKey));
        uint256 finalRecipientBalance = token.balanceOf(recipient);
        
        console.log("Sender balance after:", finalSenderBalance);
        console.log("Recipient balance after:", finalRecipientBalance);
        
        vm.stopBroadcast();
    }
}