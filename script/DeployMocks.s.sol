// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/OrderBook.sol";

import {IOrderBook} from "../src/OrderBook.sol";
import "../src/PoolManager.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "./DeployHelpers.s.sol";
import "forge-std/console.sol";

contract DeployMocks is DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";
    string constant WBTC_ADDRESS = "MOCK_TOKEN_WBTC";
    string constant POOLS_CREATED = "POOLS_CREATED";

    // Default fee settings
    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 2; // 0.2%

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;

    // Mock tokens
    MockUSDC mockUSDC;
    MockWETH mockWETH;
    MockToken mockWBTC;

    // Test mode flag
    bool shouldDeployMocks;
    bool shouldCreatePools;

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();

        loadDeployments();

        shouldDeployMocks =
            !deployed[WETH_ADDRESS].isSet || !deployed[USDC_ADDRESS].isSet || !deployed[WBTC_ADDRESS].isSet;

        shouldCreatePools = !deployed[POOLS_CREATED].isSet;

        printConfiguration();

        vm.startBroadcast(deployerPrivateKey);

        if (shouldDeployMocks) {
            deployMockTokens();
        } else {
            loadMockTokens();
        }

        loadCoreContracts();

        if (shouldCreatePools) {
            createTradingPools();
        }

        vm.stopBroadcast();

        exportDeployments();
        printDeployments();
    }

    function loadCoreContracts() private {
        console.log("\n=== Loading Core Contracts ===");

        address balanceManagerAddress = deployed[BALANCE_MANAGER_ADDRESS].addr;
        address poolManagerAddress = deployed[POOL_MANAGER_ADDRESS].addr;
        address gtxRouterAddress = deployed[GTX_ROUTER_ADDRESS].addr;

        require(balanceManagerAddress != address(0), "BalanceManager address not found in deployments");
        require(poolManagerAddress != address(0), "PoolManager address not found in deployments");
        require(gtxRouterAddress != address(0), "GTXRouter address not found in deployments");

        balanceManager = BalanceManager(balanceManagerAddress);
        poolManager = PoolManager(poolManagerAddress);
        gtxRouter = GTXRouter(gtxRouterAddress);

        console.log("BalanceManager:", address(balanceManager));
        console.log("PoolManager:", address(poolManager));
        console.log("GTXRouter:", address(gtxRouter));
    }

    function deployMockTokens() private {
        console.log("\n=== Deploying Mock Tokens ===");

        // Deploy new tokens
        mockWETH = new MockWETH();
        mockUSDC = new MockUSDC();
        mockWBTC = new MockToken("Mock WBTC", "mWBTC", 8);

        // Store in deployments
        deployments.push(Deployment(WETH_ADDRESS, address(mockWETH)));
        deployments.push(Deployment(USDC_ADDRESS, address(mockUSDC)));
        deployments.push(Deployment(WBTC_ADDRESS, address(mockWBTC)));

        // Add to deployed mapping
        deployed[WETH_ADDRESS] = DeployedContract(address(mockWETH), true);
        deployed[USDC_ADDRESS] = DeployedContract(address(mockUSDC), true);
        deployed[WBTC_ADDRESS] = DeployedContract(address(mockWBTC), true);

        console.log("Deployed MockWETH:", address(mockWETH));
        console.log("Deployed MockUSDC:", address(mockUSDC));
        console.log("Deployed MockWBTC:", address(mockWBTC));
    }

    function loadMockTokens() private {
        console.log("\n=== Loading Mock Tokens ===");

        address wethAddr = deployed[WETH_ADDRESS].addr;
        address usdcAddr = deployed[USDC_ADDRESS].addr;
        address wbtcAddr = deployed[WBTC_ADDRESS].addr;

        require(wethAddr != address(0), "WETH address not found in deployments");
        require(usdcAddr != address(0), "USDC address not found in deployments");
        require(wbtcAddr != address(0), "WBTC address not found in deployments");

        mockWETH = MockWETH(wethAddr);
        mockUSDC = MockUSDC(usdcAddr);
        mockWBTC = MockToken(wbtcAddr);

        console.log("Loaded MockWETH:", address(mockWETH));
        console.log("Loaded MockUSDC:", address(mockUSDC));
        console.log("Loaded MockWBTC:", address(mockWBTC));
    }

    function createTradingPools() private {
        console.log("\n=== Creating Trading Pools ===");
        vm.allowCheatcodes(address(poolManager));
        Currency quoteUsdc = Currency.wrap(address(mockUSDC));

        // Create WETH/USDC pool
        IOrderBook.TradingRules memory wethUsdcRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH
            minAmountMovement: 1e14, // 0.0001 ETH
            minOrderSize: 1e4, // 0.01 USDC
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
        });
        Currency baseWeth = Currency.wrap(address(mockWETH));
        IPoolManager(poolManager).createPool(baseWeth, quoteUsdc, wethUsdcRules);

        // Create WBTC/USDC pool
        IOrderBook.TradingRules memory wbtcUsdcRules = IOrderBook.TradingRules({
            minTradeAmount: 1e3, // 0.00001 BTC (8 decimals)
            minAmountMovement: 1e3, // 0.00001 BTC (8 decimals)
            minOrderSize: 1e4, // 0.01 USDC (6 decimals)
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
        });
        Currency baseWbtc = Currency.wrap(address(mockWBTC));
        IPoolManager(poolManager).createPool(baseWbtc, quoteUsdc, wbtcUsdcRules);

        // Mark pools as created
        deployments.push(Deployment(POOLS_CREATED, address(1)));
        deployed[POOLS_CREATED] = DeployedContract(address(1), true);
    }

    function printConfiguration() private view {
        console.log("\n=== Configuration ===");
        console.log("Deploy Mocks: %s", shouldDeployMocks ? "Yes" : "No");
        console.log("Create Pools: %s", shouldCreatePools ? "Yes" : "No");
    }

    function printDeployments() private view {
        console.log("\n=== Deployments ===");
        for (uint256 i = 0; i < deployments.length; i++) {
            console.log("%s: %s", deployments[i].name, deployments[i].addr);
        }
    }
}
