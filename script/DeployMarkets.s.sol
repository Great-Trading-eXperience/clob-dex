// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/OrderBook.sol";
import {IOrderBook} from "../src/OrderBook.sol";
import "../src/PoolManager.sol";
import "../src/mocks/MockToken.sol";
import "./DeployHelpers.s.sol";
import "forge-std/console.sol";

contract DeployMarkets is DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant MARKETS_CREATED = "MARKETS_CREATED";
    
    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    
    // Market configuration
    struct MarketConfig {
        string name;        
        address baseToken;  
        address quoteToken; 
        uint256 baseDecimals;  
        uint256 quoteDecimals; 
        uint128 minTradeAmount;    
        uint128 minAmountMovement; 
        uint128 minOrderSize;      
        uint128 minPriceMovement;  
    }
    
    MarketConfig[] markets;
    
    function run() public {
        loadDeployments();
        
        uint256 deployerPrivateKey = getDeployerKey();
        
        loadCoreContracts();
        
        configureMarkets();
        
        vm.startBroadcast(deployerPrivateKey);
        
        createMarkets();
        
        vm.stopBroadcast();
        
        exportDeployments();
        printDeployments();
    }
    
    function loadCoreContracts() private {
        console.log("\n========== LOADING CORE CONTRACTS ==========");
        
        address balanceManagerAddress = deployed[BALANCE_MANAGER_ADDRESS].addr;
        address poolManagerAddress = deployed[POOL_MANAGER_ADDRESS].addr;
        address gtxRouterAddress = deployed[GTX_ROUTER_ADDRESS].addr;
        
        require(balanceManagerAddress != address(0), "BalanceManager address not found in deployments");
        require(poolManagerAddress != address(0), "PoolManager address not found in deployments");
        require(gtxRouterAddress != address(0), "GTXRouter address not found in deployments");
        
        balanceManager = BalanceManager(balanceManagerAddress);
        poolManager = PoolManager(poolManagerAddress);
        gtxRouter = GTXRouter(gtxRouterAddress);
        
        console.log("BalanceManager: %s", address(balanceManager));
        console.log("PoolManager: %s", address(poolManager));
        console.log("GTXRouter: %s", address(gtxRouter));
    }
    
    function configureMarkets() private {
        console.log("\n========== CONFIGURING MARKETS ==========");
        
        address usdcAddress = getTokenAddress("MOCK_TOKEN_USDC");
        address wethAddress = getTokenAddress("MOCK_TOKEN_WETH");
        address wbtcAddress = getTokenAddress("MOCK_TOKEN_WBTC");
        
        if (wethAddress != address(0) && usdcAddress != address(0)) {
            markets.push(MarketConfig({
                name: "WETH/USDC",
                baseToken: wethAddress,
                quoteToken: usdcAddress,
                baseDecimals: 18,
                quoteDecimals: 6,
                minTradeAmount: 1e14,    
                minAmountMovement: 1e14, 
                minOrderSize: 1e4,       
                minPriceMovement: 1e4    
            }));
            console.log("Added WETH/USDC market configuration");
        }
        
        if (wbtcAddress != address(0) && usdcAddress != address(0)) {
            markets.push(MarketConfig({
                name: "WBTC/USDC",
                baseToken: wbtcAddress,
                quoteToken: usdcAddress,
                baseDecimals: 8,
                quoteDecimals: 6,
                minTradeAmount: 1e3,     
                minAmountMovement: 1e3,  
                minOrderSize: 1e4,       
                minPriceMovement: 1e4    
            }));
            console.log("Added WBTC/USDC market configuration");
        }
        
        console.log("Configured %d markets for deployment", markets.length);
    }
    
    function createMarkets() private {
        console.log("\n========== CREATING MARKETS ==========");
        
        vm.allowCheatcodes(address(poolManager));
        
        for (uint256 i = 0; i < markets.length; i++) {
            MarketConfig memory market = markets[i];
            
            console.log("\nCreating %s market:", market.name);
            console.log("Base Token: %s", market.baseToken);
            console.log("Quote Token: %s", market.quoteToken);
            
            IOrderBook.TradingRules memory rules = IOrderBook.TradingRules({
                minTradeAmount: market.minTradeAmount,
                minAmountMovement: market.minAmountMovement,
                minOrderSize: market.minOrderSize,
                minPriceMovement: market.minPriceMovement
            });
            
            Currency baseToken = Currency.wrap(market.baseToken);
            Currency quoteToken = Currency.wrap(market.quoteToken);
            
            try IPoolManager(poolManager).createPool(baseToken, quoteToken, rules) {
                console.log("Successfully created %s market", market.name);
                
                string memory poolKey = string(abi.encodePacked("POOL_", market.name));
                
                PoolKey memory key = IPoolManager(poolManager).createPoolKey(baseToken, quoteToken);
                IPoolManager.Pool memory pool = IPoolManager(poolManager).getPool(key);
                
                if (address(pool.orderBook) != address(0)) {
                    address orderBookAddress = address(pool.orderBook);
                    deployments.push(Deployment(poolKey, orderBookAddress));
                    deployed[poolKey] = DeployedContract(orderBookAddress, true);
                    console.log("OrderBook address: %s", orderBookAddress);
                }
            } catch Error(string memory reason) {
                console.log("Failed to create %s market: %s", market.name, reason);
            } catch {
                console.log("Failed to create %s market with unknown error", market.name);
            }
        }
        
        deployments.push(Deployment(MARKETS_CREATED, address(1)));
        deployed[MARKETS_CREATED] = DeployedContract(address(1), true);
    }
    
    function getTokenAddress(string memory key) private view returns (address) {
        if (deployed[key].isSet) {
            return deployed[key].addr;
        }
        return address(0);
    }
    
    function printDeployments() private view {
        console.log("\n========== DEPLOYMENTS ==========");
        for (uint256 i = 0; i < deployments.length; i++) {
            console.log("%s: %s", deployments[i].name, deployments[i].addr);
        }
    }
}
