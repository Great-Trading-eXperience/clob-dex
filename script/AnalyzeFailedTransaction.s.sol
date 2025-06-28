// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {BalanceManager} from "../src/BalanceManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AnalyzeFailedTransaction is Script, DeployHelpers {
    // Contract address keys from deployments
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";
    string constant WBTC_ADDRESS = "MOCK_TOKEN_WBTC";
    
    // Core contracts
    BalanceManager balanceManager;
    
    // Mock tokens
    MockToken weth;
    MockToken usdc;
    MockToken wbtc;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        // Load core contracts
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        
        // Load mock tokens
        weth = MockToken(deployed[WETH_ADDRESS].addr);
        usdc = MockToken(deployed[USDC_ADDRESS].addr);
        wbtc = MockToken(deployed[WBTC_ADDRESS].addr);
    }

    function run() external view {
        // Get private keys and derive addresses
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 deployerPrivateKey2 = vm.envUint("PRIVATE_KEY_2");
        
        address ownerFromPrivateKey = vm.addr(deployerPrivateKey);
        address owner2FromPrivateKey = vm.addr(deployerPrivateKey2);
        
        // Get owner address from env (this might be different)
        address ownerFromEnv = vm.envAddress("OWNER_ADDRESS");
        
        console.log("=== ADDRESS ANALYSIS ===");
        console.log("Address from PRIVATE_KEY:", ownerFromPrivateKey);
        console.log("Address from PRIVATE_KEY_2:", owner2FromPrivateKey);
        console.log("Address from OWNER_ADDRESS:", ownerFromEnv);
        console.log("DefaultSender (from forge):", tx.origin);
        
        console.log("\n=== CONTRACT ADDRESSES ===");
        console.log("BalanceManager Proxy:", address(balanceManager));
        console.log("WETH Token:", address(weth));
        console.log("USDC Token:", address(usdc));
        console.log("WBTC Token:", address(wbtc));
        
        // Expected addresses from your error trace
        address expectedBalanceManager = 0xd3168EBb535cDFff693af02045c39BfdE230813D;
        address expectedWETH = 0x01665f1847a513bf4C1f8AC498Bd31a2bAa3E3D3;
        address expectedUSDC = 0x4b9A14Ca8b00b6D83c8D663a4D9471A79CA6f58e;
        address expectedWBTC = 0x3858005bA8795D6dF8047f0F3C47CC7d6B75976b;
        
        console.log("\n=== EXPECTED ADDRESSES FROM ERROR ===");
        console.log("Expected BalanceManager:", expectedBalanceManager);
        console.log("Expected WETH:", expectedWETH);
        console.log("Expected USDC:", expectedUSDC);
        console.log("Expected WBTC:", expectedWBTC);
        
        // Check if addresses match
        console.log("\n=== ADDRESS MATCHING ===");
        console.log("BalanceManager matches:", address(balanceManager) == expectedBalanceManager);
        console.log("WETH matches:", address(weth) == expectedWETH);
        console.log("USDC matches:", address(usdc) == expectedUSDC);
        console.log("WBTC matches:", address(wbtc) == expectedWBTC);
        
        // Check balances for all relevant addresses
        address[] memory addressesToCheck = new address[](4);
        addressesToCheck[0] = ownerFromPrivateKey;
        addressesToCheck[1] = owner2FromPrivateKey;
        addressesToCheck[2] = ownerFromEnv;
        addressesToCheck[3] = tx.origin;
        
        string[] memory addressLabels = new string[](4);
        addressLabels[0] = "PRIVATE_KEY address";
        addressLabels[1] = "PRIVATE_KEY_2 address";
        addressLabels[2] = "OWNER_ADDRESS";
        addressLabels[3] = "tx.origin";
        
        for (uint i = 0; i < addressesToCheck.length; i++) {
            address addr = addressesToCheck[i];
            string memory label = addressLabels[i];
            
            console.log("\n=== BALANCES FOR", label, "===");
            console.log("Address:", addr);
            
            // Token balances
            console.log("WETH balance:", weth.balanceOf(addr));
            console.log("USDC balance:", usdc.balanceOf(addr));
            console.log("WBTC balance:", wbtc.balanceOf(addr));
            
            // Token allowances to BalanceManager
            console.log("WETH allowance to BalanceManager:", weth.allowance(addr, address(balanceManager)));
            console.log("USDC allowance to BalanceManager:", usdc.allowance(addr, address(balanceManager)));
            console.log("WBTC allowance to BalanceManager:", wbtc.allowance(addr, address(balanceManager)));
            
            // BalanceManager internal balances
            console.log("BalanceManager WETH balance:", balanceManager.getBalance(addr, Currency.wrap(address(weth))));
            console.log("BalanceManager USDC balance:", balanceManager.getBalance(addr, Currency.wrap(address(usdc))));
            console.log("BalanceManager WBTC balance:", balanceManager.getBalance(addr, Currency.wrap(address(wbtc))));
        }
        
        // Check if tokens exist at expected addresses (might be on different network)
        console.log("\n=== CHECKING EXPECTED TOKEN ADDRESSES ===");
        console.log("Code size at expected WETH:", expectedWETH.code.length);
        console.log("Code size at expected USDC:", expectedUSDC.code.length);
        console.log("Code size at expected WBTC:", expectedWBTC.code.length);
        console.log("Code size at expected BalanceManager:", expectedBalanceManager.code.length);
        
        // Error analysis - the specific error shows:
        // ERC20InsufficientAllowance(0xd3168EBb535cDFff693af02045c39BfdE230813D, 0, 950000000)
        // This means: spender=0xd3168EBb535cDFff693af02045c39BfdE230813D, allowance=0, needed=950000000
        console.log("\n=== ERROR ANALYSIS ===");
        console.log("Error: ERC20InsufficientAllowance");
        console.log("Spender (BalanceManager):", expectedBalanceManager);
        console.log("Current allowance: 0");
        console.log("Required amount: 950000000");
        
        // Check token decimals to understand the amount
        if (expectedUSDC.code.length > 0) {
            try MockToken(expectedUSDC).decimals() returns (uint8 decimals) {
                console.log("Expected USDC decimals:", decimals);
                console.log("Required amount in human terms:", 950000000 / (10 ** decimals));
            } catch {
                console.log("Could not get decimals from expected USDC address");
            }
        }
        
        console.log("\n=== RECOMMENDATIONS ===");
        console.log("1. Verify you're on the correct network (chain ID)");
        console.log("2. Check if token addresses match between local and target network");
        console.log("3. Ensure the address derived from PRIVATE_KEY has sufficient token balance");
        console.log("4. Approve tokens to the correct BalanceManager address before transaction");
        console.log("5. Verify BalanceManager proxy address is correct for your target network");
    }
}

// Helper import for Currency type
import {Currency} from "../src/libraries/Currency.sol";