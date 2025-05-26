// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "./DeployHelpers.s.sol";
import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/PoolManager.sol";
import "../src/mocks/MockToken.sol";
import "../src/marketmaker/GTXMarketMakerVault.sol";
import "../src/marketmaker/GTXMarketMakerFactory.sol";
import "../src/resolvers/PoolManagerResolver.sol";
import "forge-std/console.sol";

contract MarketMakerOrdersScript is DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant MARKET_MAKER_FACTORY_ADDRESS = "MARKET_MAKER_FACTORY";
    
    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    GTXMarketMakerFactory factory;
    PoolManagerResolver poolManagerResolver;
    
    // Market maker vault
    GTXMarketMakerVault vault;
    
    // Order parameters (can be modified as needed)
    uint128 constant BUY_PRICE = 1900 * 10**6;  
    uint128 constant SELL_PRICE = 2100 * 10**6; 
    uint128 constant ORDER_QUANTITY = 0.1 * 10**18; 
    
    address vaultAddress;
    
    function run() public {
        loadDeployments();
        
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        
        loadCoreContracts();
        
        poolManagerResolver = new PoolManagerResolver();
        
        selectVault();
        
        if (vaultAddress == address(0)) {
            console.log("No vault selected. Exiting.");
            return;
        }
        
        vault = GTXMarketMakerVault(vaultAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        placeLimitOrders();
        
        // placeMarketOrders();
        
        // rebalanceVault();
        
        vm.stopBroadcast();
    }
    
    function loadCoreContracts() private {
        console.log("\n========== LOADING CORE CONTRACTS ==========");
        
        address balanceManagerAddress = deployed[BALANCE_MANAGER_ADDRESS].addr;
        address poolManagerAddress = deployed[POOL_MANAGER_ADDRESS].addr;
        address gtxRouterAddress = deployed[GTX_ROUTER_ADDRESS].addr;
        address factoryAddress = deployed[MARKET_MAKER_FACTORY_ADDRESS].addr;
        
        require(balanceManagerAddress != address(0), "BalanceManager address not found in deployments");
        require(poolManagerAddress != address(0), "PoolManager address not found in deployments");
        require(gtxRouterAddress != address(0), "GTXRouter address not found in deployments");
        require(factoryAddress != address(0), "Market Maker Factory address not found in deployments");
        
        balanceManager = BalanceManager(balanceManagerAddress);
        poolManager = PoolManager(poolManagerAddress);
        gtxRouter = GTXRouter(gtxRouterAddress);
        factory = GTXMarketMakerFactory(factoryAddress);
        
        console.log("BalanceManager: %s", address(balanceManager));
        console.log("PoolManager: %s", address(poolManager));
        console.log("GTXRouter: %s", address(gtxRouter));
        console.log("MarketMakerFactory: %s", address(factory));
    }
    
    function selectVault() private {
        console.log("\n========== SELECTING MARKET MAKER VAULT ==========");
        
        // Try to get vaults from factory
        try factory.getVaults() returns (address[] memory vaults) {
            if (vaults.length == 0) {
                console.log("No vaults found in factory");
                return;
            }
            
            console.log("Found %d vaults:", vaults.length);
            
            for (uint256 i = 0; i < vaults.length; i++) {
                GTXMarketMakerVault mmVault = GTXMarketMakerVault(vaults[i]);
                
                try mmVault.name() returns (string memory vaultName) {
                    try mmVault.symbol() returns (string memory vaultSymbol) {
                        console.log("%d: %s (%s) - %s", i, vaultName, vaultSymbol, vaults[i]);
                    } catch {
                        console.log("%d: <Unknown Symbol> - %s", i, vaults[i]);
                    }
                } catch {
                    console.log("%d: <Unknown Name> - %s", i, vaults[i]);
                }
            }
            
            if (vaults.length > 0) {
                vaultAddress = vaults[0];
                GTXMarketMakerVault selectedVault = GTXMarketMakerVault(vaultAddress);
                
                string memory vaultName = "";
                string memory vaultSymbol = "";
                
                try selectedVault.name() returns (string memory name) {
                    vaultName = name;
                } catch {}
                
                try selectedVault.symbol() returns (string memory symbol) {
                    vaultSymbol = symbol;
                } catch {}
                
                console.log("\nSelected vault: %s (%s)", vaultName, vaultSymbol);
                console.log("Vault address: %s", vaultAddress);
                
                // Display vault parameters
                displayVaultParameters(selectedVault);
            }
        } catch {
            console.log("Failed to get vaults from factory");
        }
    }
    
    function displayVaultParameters(GTXMarketMakerVault selectedVault) private view {
        console.log("\n========== VAULT PARAMETERS ==========");
        
        try selectedVault.getBaseToken() returns (address baseToken) {
            console.log("Base Token: %s", baseToken);
        } catch {
            console.log("Failed to get base token");
        }
        
        try selectedVault.getQuoteToken() returns (address quoteToken) {
            console.log("Quote Token: %s", quoteToken);
        } catch {
            console.log("Failed to get quote token");
        }
        
        try selectedVault.getCurrentPrice() returns (uint128 currentPrice) {
            console.log("Current Price: %d (quote decimals)", currentPrice);
        } catch {
            console.log("Failed to get current price");
        }
        
        try selectedVault.getTotalValue() returns (uint256 totalValue) {
            console.log("Total Value: %d (quote decimals)", totalValue);
        } catch {
            console.log("Failed to get total value");
        }
    }
    
    function placeLimitOrders() private {
        console.log("\n========== PLACING LIMIT ORDERS ==========");
        
        try vault.placeOrder(
            BUY_PRICE,
            ORDER_QUANTITY,
            IOrderBook.Side.BUY
        ) returns (uint48 buyOrderId) {
            console.log("Buy order placed successfully");
            console.log("Order ID: %d", buyOrderId);
            console.log("Price: %d USDC", BUY_PRICE / 10**6);
            console.log("Quantity: %d ETH", ORDER_QUANTITY / 10**18);
        } catch Error(string memory reason) {
            console.log("Failed to place buy order: %s", reason);
        } catch {
            console.log("Failed to place buy order with unknown error");
        }
        
        try vault.placeOrder(
            SELL_PRICE,
            ORDER_QUANTITY,
            IOrderBook.Side.SELL
        ) returns (uint48 sellOrderId) {
            console.log("\nSell order placed successfully");
            console.log("Order ID: %d", sellOrderId);
            console.log("Price: %d USDC", SELL_PRICE / 10**6);
            console.log("Quantity: %d ETH", ORDER_QUANTITY / 10**18);
        } catch Error(string memory reason) {
            console.log("Failed to place sell order: %s", reason);
        } catch {
            console.log("Failed to place sell order with unknown error");
        }
    }
    
    function placeMarketOrders() private {
        console.log("\n========== PLACING MARKET ORDERS ==========");
        
        try vault.placeMarketOrder(
            ORDER_QUANTITY,
            IOrderBook.Side.BUY
        ) returns (uint48 buyOrderId) {
            console.log("Market buy order placed successfully");
            console.log("Order ID: %d", buyOrderId);
            console.log("Quantity: %d ETH", ORDER_QUANTITY / 10**18);
        } catch Error(string memory reason) {
            console.log("Failed to place market buy order: %s", reason);
        } catch {
            console.log("Failed to place market buy order with unknown error");
        }
        
        try vault.placeMarketOrder(
            ORDER_QUANTITY,
            IOrderBook.Side.SELL
        ) returns (uint48 sellOrderId) {
            console.log("\nMarket sell order placed successfully");
            console.log("Order ID: %d", sellOrderId);
            console.log("Quantity: %d ETH", ORDER_QUANTITY / 10**18);
        } catch Error(string memory reason) {
            console.log("Failed to place market sell order: %s", reason);
        } catch {
            console.log("Failed to place market sell order with unknown error");
        }
    }
    
    function rebalanceVault() private {
        console.log("\n========== REBALANCING VAULT ==========");
        
        try vault.rebalance() {
            console.log("Vault rebalanced successfully");
        } catch Error(string memory reason) {
            console.log("Failed to rebalance vault: %s", reason);
        } catch {
            console.log("Failed to rebalance vault with unknown error");
        }
    }
}
