// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Currency} from "../src/core/libraries/Currency.sol";

interface IBalanceManager {
    function getBalance(address user, Currency currency) external view returns (uint256);
}

contract DebugBalanceCheck is Script {
    address constant BALANCE_MANAGER = 0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5;
    address constant RECIPIENT = 0x84d437fFC072a2c9E7E16d688D46b4Dbc95dd5e2;
    address constant gUSDT = 0xf2dc96d3e25f06e7458fF670Cf1c9218bBb71D9d;

    function run() external view {
        console.log("=== Debug Balance Check ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("Recipient:", RECIPIENT);
        console.log("gUSDT:", gUSDT);
        console.log("");
        
        // Try to call getBalance with try/catch equivalent
        IBalanceManager balanceManager = IBalanceManager(BALANCE_MANAGER);
        
        console.log("Attempting to call getBalance...");
        try balanceManager.getBalance(RECIPIENT, Currency.wrap(gUSDT)) returns (uint256 balance) {
            console.log("SUCCESS - Balance:", balance);
            console.log("Balance readable:", balance / 1e6, "USDT");
        } catch Error(string memory reason) {
            console.log("ERROR - Reason:", reason);
        } catch (bytes memory) {
            console.log("ERROR - Low-level revert");
        }
    }
}