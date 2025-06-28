// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";

contract CheckTokenBalances is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    // Mock tokens
    MockWETH mockWETH;
    MockUSDC mockUSDC;
    address balanceManager;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        // Load balance manager address
        balanceManager = deployed[BALANCE_MANAGER_ADDRESS].addr;
        
        // Load mock tokens
        mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
        mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        
        console.log("=== Token Balance and Approval Check ===");
        console.log("Owner address:", owner);
        console.log("Balance Manager address:", balanceManager);
        console.log("");
        
        // Check WETH
        console.log("=== WETH Token ===");
        console.log("Address:", address(mockWETH));
        uint256 wethBalance = mockWETH.balanceOf(owner);
        uint256 wethAllowance = mockWETH.allowance(owner, balanceManager);
        console.log("Balance:", wethBalance);
        console.log("Allowance to BalanceManager:", wethAllowance);
        console.log("");
        
        // Check USDC
        console.log("=== USDC Token ===");
        console.log("Address:", address(mockUSDC));
        uint256 usdcBalance = mockUSDC.balanceOf(owner);
        uint256 usdcAllowance = mockUSDC.allowance(owner, balanceManager);
        console.log("Balance:", usdcBalance);
        console.log("Allowance to BalanceManager:", usdcAllowance);
        console.log("");
        
        // Check if we have enough balance and allowance
        console.log("=== Analysis ===");
        if (wethBalance > 0) {
            console.log("[OK] WETH balance available");
        } else {
            console.log("[ERROR] No WETH balance found");
        }
        
        if (usdcBalance > 0) {
            console.log("[OK] USDC balance available");
        } else {
            console.log("[ERROR] No USDC balance found");
        }
        
        if (wethAllowance > 0) {
            console.log("[OK] WETH allowance set");
        } else {
            console.log("[WARNING] No WETH allowance for BalanceManager");
        }
        
        if (usdcAllowance > 0) {
            console.log("[OK] USDC allowance set");
        } else {
            console.log("[WARNING] No USDC allowance for BalanceManager");
        }
    }
}