// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function mint(address account, uint256 amount) external;
}

interface IChainBalanceManager {
    function deposit(address token, uint256 amount, address recipient) external payable;
}

contract DepositWithMessageTracking is Script {
    // Hyperlane MessageSent event signature
    bytes32 constant MESSAGE_SENT_SIGNATURE = 0x788dbc1b7152732178210e7f4d9d010ef016f9eafbe66786bd7169f56e0c353a;
    
    address constant CHAIN_BALANCE_MANAGER = 0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7;
    address constant MAILBOX = 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1;
    address constant USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("=== Deposit with Message ID Tracking ===");
        
        // Setup token
        IERC20 usdt = IERC20(USDT);
        uint256 amount = 50 * 10 ** 6; // 50 USDT
        address recipient = 0x84d437fFC072a2c9E7E16d688D46b4Dbc95dd5e2;
        
        // Ensure sufficient balance
        if (usdt.balanceOf(deployer) < amount) {
            usdt.mint(deployer, amount * 2);
        }
        
        // Approve and record logs
        usdt.approve(CHAIN_BALANCE_MANAGER, amount);
        
        console.log("Recording logs before deposit...");
        vm.recordLogs();
        
        // Execute deposit
        IChainBalanceManager(CHAIN_BALANCE_MANAGER).deposit(USDT, amount, recipient);
        console.log("Deposit executed, parsing logs...");
        
        // Get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Parse logs to find MessageSent event
        bytes32 messageId = parseMessageIdFromLogs(logs, MAILBOX);
        
        if (messageId != bytes32(0)) {
            console.log("SUCCESS: Message ID found:", vm.toString(messageId));
            console.log("Track at: https://hyperlane-explorer.gtxdex.xyz/message/", vm.toString(messageId));
        } else {
            console.log("WARNING: No MessageSent event found");
        }
        
        vm.stopBroadcast();
    }
    
    function parseMessageIdFromLogs(Vm.Log[] memory logs, address mailboxAddress) internal pure returns (bytes32) {
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            
            // Check if this log is from the mailbox and has the MessageSent signature
            if (log.emitter == mailboxAddress && 
                log.topics.length > 0 && 
                log.topics[0] == MESSAGE_SENT_SIGNATURE) {
                
                // MessageSent event has messageId as the second topic (first indexed parameter)
                if (log.topics.length > 1) {
                    return log.topics[1];
                }
            }
        }
        return bytes32(0);
    }
}