// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

contract CheckRiseNetwork is Script {
    // Addresses from Rise network (chain ID 11155931)
    address constant BALANCE_MANAGER = 0xd3168EBb535cDFff693af02045c39BfdE230813D;
    address constant USDC_TOKEN = 0x4b9A14Ca8b00b6D83c8D663a4D9471A79CA6f58e;
    address constant WBTC_TOKEN = 0x3858005bA8795D6dF8047f0F3C47CC7d6B75976b;
    address constant WETH_TOKEN = 0x01665f1847a513bf4C1f8AC498Bd31a2bAa3E3D3;
    
    function run() external view {
        console.log("=== RISE NETWORK ANALYSIS ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block number:", block.number);
        
        // Get the address from PRIVATE_KEY
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(privateKey);
        
        console.log("User Address:", userAddress);
        console.log("ETH Balance:", userAddress.balance);
        
        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("BalanceManager:", BALANCE_MANAGER);
        console.log("USDC Token:", USDC_TOKEN);
        console.log("WBTC Token:", WBTC_TOKEN);
        console.log("WETH Token:", WETH_TOKEN);
        
        console.log("\n=== CONTRACT CODE VERIFICATION ===");
        console.log("BalanceManager code size:", BALANCE_MANAGER.code.length);
        console.log("USDC code size:", USDC_TOKEN.code.length);
        console.log("WBTC code size:", WBTC_TOKEN.code.length);
        console.log("WETH code size:", WETH_TOKEN.code.length);
        
        // Check token balances and allowances if contracts exist
        if (USDC_TOKEN.code.length > 0) {
            console.log("\n=== USDC TOKEN ANALYSIS ===");
            
            // Get token balance
            (bool success, bytes memory balanceData) = USDC_TOKEN.staticcall(
                abi.encodeWithSignature("balanceOf(address)", userAddress)
            );
            if (success) {
                uint256 balance = abi.decode(balanceData, (uint256));
                console.log("USDC Balance:", balance);
            } else {
                console.log("Failed to get USDC balance");
            }
            
            // Get allowance to BalanceManager
            (bool allowanceSuccess, bytes memory allowanceData) = USDC_TOKEN.staticcall(
                abi.encodeWithSignature("allowance(address,address)", userAddress, BALANCE_MANAGER)
            );
            if (allowanceSuccess) {
                uint256 allowance = abi.decode(allowanceData, (uint256));
                console.log("USDC Allowance to BalanceManager:", allowance);
            } else {
                console.log("Failed to get USDC allowance");
            }
            
            // Get token decimals
            (bool decimalsSuccess, bytes memory decimalsData) = USDC_TOKEN.staticcall(
                abi.encodeWithSignature("decimals()")
            );
            if (decimalsSuccess) {
                uint8 decimals = abi.decode(decimalsData, (uint8));
                console.log("USDC Decimals:", decimals);
                console.log("Required amount (950000000) in human terms:", 950000000 / (10 ** decimals));
            } else {
                console.log("Failed to get USDC decimals");
            }
        }
        
        if (WETH_TOKEN.code.length > 0) {
            console.log("\n=== WETH TOKEN ANALYSIS ===");
            
            // Get token balance
            (bool success, bytes memory balanceData) = WETH_TOKEN.staticcall(
                abi.encodeWithSignature("balanceOf(address)", userAddress)
            );
            if (success) {
                uint256 balance = abi.decode(balanceData, (uint256));
                console.log("WETH Balance:", balance);
            } else {
                console.log("Failed to get WETH balance");
            }
            
            // Get allowance to BalanceManager
            (bool allowanceSuccess, bytes memory allowanceData) = WETH_TOKEN.staticcall(
                abi.encodeWithSignature("allowance(address,address)", userAddress, BALANCE_MANAGER)
            );
            if (allowanceSuccess) {
                uint256 allowance = abi.decode(allowanceData, (uint256));
                console.log("WETH Allowance to BalanceManager:", allowance);
            } else {
                console.log("Failed to get WETH allowance");
            }
        }
        
        if (WBTC_TOKEN.code.length > 0) {
            console.log("\n=== WBTC TOKEN ANALYSIS ===");
            
            // Get token balance
            (bool success, bytes memory balanceData) = WBTC_TOKEN.staticcall(
                abi.encodeWithSignature("balanceOf(address)", userAddress)
            );
            if (success) {
                uint256 balance = abi.decode(balanceData, (uint256));
                console.log("WBTC Balance:", balance);
            } else {
                console.log("Failed to get WBTC balance");
            }
            
            // Get allowance to BalanceManager
            (bool allowanceSuccess, bytes memory allowanceData) = WBTC_TOKEN.staticcall(
                abi.encodeWithSignature("allowance(address,address)", userAddress, BALANCE_MANAGER)
            );
            if (allowanceSuccess) {
                uint256 allowance = abi.decode(allowanceData, (uint256));
                console.log("WBTC Allowance to BalanceManager:", allowance);
            } else {
                console.log("Failed to get WBTC allowance");
            }
        }
        
        console.log("\n=== SOLUTION ===");
        console.log("The error 'ERC20InsufficientAllowance' means:");
        console.log("1. Your address needs to approve the tokens to the BalanceManager");
        console.log("2. You're likely on the Rise network (chain 11155931), not local (31337)");
        console.log("3. Run token approval transactions before your main transaction");
        
        console.log("\nExample commands to fix:");
        console.log("1. Switch to Rise network: --rpc-url riseSepolia");
        console.log("2. Approve USDC:");
        console.log("   cast send", USDC_TOKEN, "\"approve(address,uint256)\"", BALANCE_MANAGER);
        console.log("   115792089237316195423570985008687907853269984665640564039457584007913129639935");
        console.log("   --private-key $PRIVATE_KEY --rpc-url riseSepolia");
        console.log("3. Then retry your original transaction");
    }
}