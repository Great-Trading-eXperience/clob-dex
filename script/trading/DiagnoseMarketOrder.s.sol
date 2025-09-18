// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/GTXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Diagnose Market Order Issues
 * @dev Minimal script to debug MemoryOOG issues with very small quantities
 */
contract DiagnoseMarketOrder is DeployHelpers {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        loadDeployments();
        
        // Load contracts
        BalanceManager balanceManager = BalanceManager(deployed["PROXY_BALANCEMANAGER"].addr);
        GTXRouter gtxRouter = GTXRouter(deployed["PROXY_ROUTER"].addr);
        PoolManager poolManager = PoolManager(deployed["PROXY_POOLMANAGER"].addr);
        
        // Load synthetic tokens
        address synthWETH = deployed["gsWETH"].addr;
        address synthUSDC = deployed["gsUSDC"].addr;
        
        Currency weth = Currency.wrap(synthWETH);
        Currency usdc = Currency.wrap(synthUSDC);
        
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== DIAGNOSTIC: Market Order Debug ===");
        console.log("Deployer:", deployer);
        console.log("gsWETH:", synthWETH);
        console.log("gsUSDC:", synthUSDC);
        
        // Check balances
        uint256 wethBalance = balanceManager.getBalance(deployer, weth);
        uint256 usdcBalance = balanceManager.getBalance(deployer, usdc);
        
        console.log("gsWETH balance:", wethBalance);
        console.log("gsUSDC balance:", usdcBalance);
        
        // Check orderbook state
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        
        console.log("Best BUY price:", bestBuy.price);
        console.log("Best BUY volume:", bestBuy.volume);
        console.log("Best SELL price:", bestSell.price);
        console.log("Best SELL volume:", bestSell.volume);
        
        // Get pool for market order
        PoolKey memory poolKey = poolManager.createPoolKey(weth, usdc);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
        
        console.log("Pool base:", Currency.unwrap(pool.baseCurrency));
        console.log("Pool quote:", Currency.unwrap(pool.quoteCurrency));
        
        // Test 1: Extremely small quantity
        console.log("\n=== TEST 1: Tiny Market SELL Order ===");
        uint128 tinyQuantity = 1000000000000; // 0.000001 ETH (1e12 wei)
        console.log("Attempting market SELL with quantity:", tinyQuantity);
        
        if (wethBalance >= tinyQuantity) {
            try gtxRouter.calculateMinOutAmountForMarket(pool, 0, IOrderBook.Side.SELL, 1000) returns (uint128 minOut) {
                console.log("Min out calculated:", minOut);
                
                // Attempt the market order
                try gtxRouter.placeMarketOrder(pool, tinyQuantity, IOrderBook.Side.SELL, 0, minOut) returns (uint48 orderId, uint128 filled) {
                    console.log("[SUCCESS] Market order placed!");
                    console.log("Order ID:", orderId);
                    console.log("Filled:", filled);
                } catch Error(string memory reason) {
                    console.log("[ERROR] Market order failed:", reason);
                } catch (bytes memory) {
                    console.log("[ERROR] Market order failed with low-level error");
                }
            } catch Error(string memory reason) {
                console.log("[ERROR] Min out calculation failed:", reason);
            } catch (bytes memory) {
                console.log("[ERROR] Min out calculation failed with low-level error");
            }
        } else {
            console.log("[ERROR] Insufficient balance for test");
        }
        
        // Test 2: Check specific price level
        console.log("\n=== TEST 2: Check Price Level Details ===");
        if (bestBuy.price > 0) {
            (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, bestBuy.price);
            console.log("Orders at best price:", orderCount);
            console.log("Total volume at best price:", totalVolume);
            
            // Check a few orders at this price
            if (orderCount > 0) {
                console.log("=== Checking individual orders ===");
                for (uint256 i = 1; i <= (orderCount < 3 ? orderCount : 3); i++) {
                    try gtxRouter.getOrder(weth, usdc, uint48(i)) returns (IOrderBook.Order memory order) {
                        console.log("Order", i, "- Price:", order.price);
                        console.log("Order", i, "- Quantity:", order.quantity);
                        console.log("Order", i, "- Filled:", order.filled);
                        console.log("Order", i, "- User:", order.user);
                        console.log("Order", i, "- Status:", uint8(order.status));
                        console.log("---");
                    } catch {
                        console.log("Order", i, "- Could not fetch");
                    }
                }
            }
        }
        
        vm.stopBroadcast();
        
        console.log("\n=== DIAGNOSTIC COMPLETE ===");
    }
}