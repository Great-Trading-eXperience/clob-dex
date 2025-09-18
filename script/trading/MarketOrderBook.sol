// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/GTXRouter.sol";
import "../../src/core/PoolManager.sol";

import "../../src/mocks/MockToken.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockWETH.sol";
import "../../src/core/resolvers/PoolManagerResolver.sol";

contract MarketOrderBook is Script, DeployHelpers {
   // Contract address keys
   string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
   string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
   string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
   string constant WETH_ADDRESS = "gsWETH";
   string constant USDC_ADDRESS = "gsUSDC";

   // Core contracts
   BalanceManager balanceManager;
   PoolManager poolManager;
   GTXRouter gtxRouter;
   PoolManagerResolver poolManagerResolver;

   // Synthetic tokens
   IERC20 synthWETH;
   IERC20 synthUSDC;

   // Track order IDs for verification
   uint48[] marketBuyOrderIds;
   uint48[] marketSellOrderIds;

   // Deployer address
   address deployerAddress;

   function setUp() public {
       loadDeployments();
       loadContracts();

       // Deploy the resolver
       poolManagerResolver = new PoolManagerResolver();
   }

   function loadContracts() private {
       // Load core contracts
       balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
       poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
       gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);

       // Load synthetic tokens
       synthWETH = IERC20(deployed[WETH_ADDRESS].addr);
       synthUSDC = IERC20(deployed[USDC_ADDRESS].addr);
   }

   function run() public {
       uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_2");
       vm.startBroadcast(deployerPrivateKey);

       deployerAddress = vm.addr(deployerPrivateKey);

       placeMarketOrdersETHUSDC();
       verifyMarketOrders();
       
       verifyMarketOrderExecution();

       vm.stopBroadcast();
   }

   function placeMarketOrdersETHUSDC() private {
       console.log("\n=== Placing Market Orders on ETH/USDC ===");

       // Get currency objects
       Currency weth = Currency.wrap(address(synthWETH));
       Currency usdc = Currency.wrap(address(synthUSDC));

       // Get the pool using the resolver
       IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

       // Setup sender with funds for market orders (use smaller amounts matching our actual balances)
       _setupFunds(1e17, 100e6); // 0.1 ETH, 100 USDC


       // Check current approvals (not needed for synthetic tokens in BalanceManager)
       uint256 wethAllowance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 usdcAllowance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthUSDC)));

       console.log("\nCurrent BalanceManager balances:");
       console.log("gsWETH balance:", wethAllowance);
       console.log("gsUSDC balance:", usdcAllowance);

       if (wethAllowance < 1e16) { // Only need 0.01 ETH for tiny market orders
           console.log("Insufficient gsWETH balance in BalanceManager");
           return;
       }

       if (usdcAllowance < 50e6) { // Only need 50 USDC for tiny market orders
           console.log("Insufficient gsUSDC balance in BalanceManager");
           return;
       }

       // Place market SELL orders (sells ETH for USDC)
       // These will execute against the BUY limit orders
       _placeMarketSellOrders(pool, 1); // 1 sell order to avoid balance exhaustion
       
       // Skip market BUY orders since we don't have SELL limit orders yet
       console.log("Skipping market BUY orders - no SELL limit orders available");

       // Print summary
       console.log("\nMarket orders placed:");
       console.log("- 1 market SELL order (selling ETH for USDC)");
       console.log("- 0 market BUY orders (skipped - no SELL limit orders)");
   }

   function _setupFunds(uint256 ethAmount, uint256 usdcAmount) private {
       // Note: Using existing synthetic token balances in BalanceManager
       // These tokens are already available from previous local deposits
       console.log("Using existing synthetic token balances in BalanceManager");
       console.log("Expected gsWETH amount:", ethAmount);
       console.log("Expected gsUSDC amount:", usdcAmount);
       
       // Check current balances in BalanceManager
       uint256 currentWETHBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 currentUSDCBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthUSDC)));
       
       console.log("Current gsWETH balance in BalanceManager:", currentWETHBalance);
       console.log("Current gsUSDC balance in BalanceManager:", currentUSDCBalance);
       
       // Verify we have sufficient balances
       require(currentWETHBalance >= ethAmount, "Insufficient gsWETH balance in BalanceManager");
       require(currentUSDCBalance >= usdcAmount, "Insufficient gsUSDC balance in BalanceManager");
   }

   function _placeMarketBuyOrders(
       IPoolManager.Pool memory pool,
       uint8 numOrders
   ) private {
       console.log("\n--- Placing Market BUY Orders ---");

       // Much smaller quantities to avoid memory issues
       uint128[] memory quantities = new uint128[](5);
       quantities[0] = 1e15;  // 0.001 ETH
       quantities[1] = 2e15;  // 0.002 ETH
       quantities[2] = 5e15;  // 0.005 ETH
       quantities[3] = 1e16;  // 0.01 ETH
       quantities[4] = 2e16;  // 0.02 ETH

       for (uint8 i = 0; i < numOrders; i++) {
           uint128 quantity = quantities[i % 5];
           
           // Calculate proper deposit amount for buy orders (need USDC)
           // Estimate price at ~2000 USDC per ETH for deposit calculation
           uint128 estimatedPrice = 2000e6;
           uint128 depositAmount = (estimatedPrice * quantity) / 1e18;
           
           // Calculate minimum output amount with 5% slippage tolerance
           uint128 minOutAmount = gtxRouter.calculateMinOutAmountForMarket(
               pool, 0, IOrderBook.Side.BUY, 500 // 5% slippage - use 0 since using BalanceManager funds
           );
           
           (uint48 orderId, uint128 filled) = gtxRouter.placeMarketOrder(
               pool,
               quantity,
               IOrderBook.Side.BUY,
               0, // Use 0 deposit amount since balances are already in BalanceManager
               minOutAmount
           );

           console.log("Placed market BUY order ID:", orderId);
           console.log("Quantity:", quantity, "ETH");
           console.log("Filled:", filled, "ETH");
           marketBuyOrderIds.push(orderId);
       }
   }

   function _placeMarketSellOrders(
       IPoolManager.Pool memory pool,
       uint8 numOrders
   ) private {
       console.log("\n--- Placing Market SELL Orders ---");

       // Much smaller quantities to avoid memory issues
       uint128[] memory quantities = new uint128[](5);
       quantities[0] = 1e15;  // 0.001 ETH
       quantities[1] = 2e15;  // 0.002 ETH
       quantities[2] = 5e15;  // 0.005 ETH
       quantities[3] = 1e16;  // 0.01 ETH
       quantities[4] = 2e16;  // 0.02 ETH

       for (uint8 i = 0; i < numOrders; i++) {
           uint128 quantity = quantities[i % 5];
           
           // For sell orders, deposit the base currency (WETH) quantity
           uint128 depositAmount = quantity;
           
           // Calculate minimum output amount with 5% slippage tolerance
           uint128 minOutAmount = gtxRouter.calculateMinOutAmountForMarket(
               pool, 0, IOrderBook.Side.SELL, 500 // 5% slippage - use 0 since using BalanceManager funds
           );
           
           (uint48 orderId, uint128 filled) = gtxRouter.placeMarketOrder(
               pool,
               quantity,
               IOrderBook.Side.SELL,
               0, // Use 0 deposit amount since balances are already in BalanceManager
               minOutAmount
           );

           console.log("Placed market SELL order ID:", orderId);
           console.log("Quantity:", quantity, "ETH");
           console.log("Filled:", filled, "ETH");
           marketSellOrderIds.push(orderId);
       }
   }

   function verifyMarketOrders() private {
       console.log("\n=== Verifying Market Orders ===");

       // Get currency objects
       Currency weth = Currency.wrap(address(synthWETH));
       Currency usdc = Currency.wrap(address(synthUSDC));

       // Check market buy orders
       console.log("\n--- Market BUY Orders ---");
       for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
           _checkOrderDetails(weth, usdc, marketBuyOrderIds[i], string(abi.encodePacked("Market BUY #", uint2str(i + 1))));
       }

       // Check market sell orders
       console.log("\n--- Market SELL Orders ---");
       for (uint256 i = 0; i < marketSellOrderIds.length; i++) {
           _checkOrderDetails(weth, usdc, marketSellOrderIds[i], string(abi.encodePacked("Market SELL #", uint2str(i + 1))));
       }

       // Check orderbook state after market orders
       console.log("\n--- Order Book State After Market Orders ---");

       // Check best prices
       IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
       IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);

       console.log("Best BUY price:", bestBuy.price, "USDC");
       console.log("Volume at best BUY:", bestBuy.volume, "ETH\n");

       console.log("Best SELL price:", bestSell.price, "USDC");
       console.log("Volume at best SELL:", bestSell.volume, "ETH\n");

       // Check balance changes
       _checkBalances();
   }

   function _checkOrderDetails(Currency base, Currency quote, uint48 orderId, string memory label) private {
       IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, orderId);

       console.log("\nOrder details for", label);
       console.log("Order ID:", orderId);
       console.log("User:", order.user);
       console.log("Side:", order.side == IOrderBook.Side.BUY ? "BUY" : "SELL");
       console.log("Type:", order.orderType == IOrderBook.OrderType.LIMIT ? "LIMIT" : "MARKET");
       console.log("Price:", order.price, "USDC");
       console.log("Quantity:", order.quantity, "ETH");
       console.log("Filled:", order.filled, "ETH");
       console.log("---");
   }

   function _checkBalances() private {
       console.log("\n--- Balance Check ---");

       // Check BalanceManager balances
       uint256 bmEthBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 bmUsdcBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthUSDC)));

       console.log("BalanceManager gsWETH balance:", bmEthBalance, "wei");
       console.log("BalanceManager gsUSDC balance:", bmUsdcBalance, "units");
       
       // Check token balances directly
       uint256 ethTokenBalance = synthWETH.balanceOf(deployerAddress);
       uint256 usdcTokenBalance = synthUSDC.balanceOf(deployerAddress);

       console.log("Direct gsWETH token balance:", ethTokenBalance, "wei");
       console.log("Direct gsUSDC token balance:", usdcTokenBalance, "units");
   }

   // Utility function to convert uint to string
   function uint2str(uint256 _i) internal pure returns (string memory str) {
       if (_i == 0) {
           return "0";
       }
       uint256 j = _i;
       uint256 length;
       while (j != 0) {
           length++;
           j /= 10;
       }
       bytes memory bstr = new bytes(length);
       uint256 k = length;
       j = _i;
       while (j != 0) {
           bstr[--k] = bytes1(uint8(48 + j % 10));
           j /= 10;
       }
       str = string(bstr);
   }

   function verifyMarketOrderExecution() private {
       console.log("\n=== Verifying Market Order Execution ===");
       
       // Get currency objects
       Currency weth = Currency.wrap(address(synthWETH));
       Currency usdc = Currency.wrap(address(synthUSDC));
       
       // Verify market orders were executed
       _verifyMarketOrdersExecuted();
       
       // Verify balance changes from market order execution
       _verifyBalanceChanges(weth, usdc);
       
       // Verify orderbook state after market orders
       _verifyOrderBookAfterMarketOrders(weth, usdc);
       
       console.log("All market order execution verifications passed!");
   }
   
   function _verifyMarketOrdersExecuted() private {
       console.log("Checking market order execution...");
       
       // Verify we attempted to place market orders
       require(marketBuyOrderIds.length > 0 || marketSellOrderIds.length > 0, "No market orders were attempted");
       
       // For market orders that were successfully placed, verify they have valid IDs
       for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
           require(marketBuyOrderIds[i] > 0, "Invalid market BUY order ID");
       }
       
       for (uint256 i = 0; i < marketSellOrderIds.length; i++) {
           require(marketSellOrderIds[i] > 0, "Invalid market SELL order ID");
       }
       
       console.log("Market orders execution verified");
   }
   
   function _verifyBalanceChanges(Currency weth, Currency usdc) private {
       console.log("Checking balance changes...");
       
       // Get current balances from BalanceManager
       uint256 userWethBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthWETH)));
       uint256 userUsdcBalance = balanceManager.getBalance(deployerAddress, Currency.wrap(address(synthUSDC)));
       uint256 bmWethBalance = userWethBalance; // Same as user balance in BalanceManager
       uint256 bmUsdcBalance = userUsdcBalance; // Same as user balance in BalanceManager
       
       // Market orders should have transferred tokens to/from balance manager
       if (marketBuyOrderIds.length > 0) {
           // BUY orders should have used USDC and possibly received WETH
           require(bmUsdcBalance > 0, "No USDC transferred to BalanceManager for BUY orders");
       }
       
       if (marketSellOrderIds.length > 0) {
           // SELL orders should have used WETH and received USDC  
           // After selling WETH, user should have received USDC (balance should increase)
           require(bmUsdcBalance > 0, "No USDC received from SELL orders");
       }
       
       // Verify user still has reasonable balances (not completely drained)
       uint256 initialWeth = 2e18; // From _setupFunds  
       uint256 initialUsdc = 2000e6; // From _setupFunds (updated)
       
       require(userWethBalance <= initialWeth, "User WETH balance increased unexpectedly beyond initial amount");
       // For SELL orders, USDC balance should increase, so remove this check
       // require(userUsdcBalance <= initialUsdc, "User USDC balance increased unexpectedly");
       
       console.log("Balance changes verification passed");
   }
   
   function _verifyOrderBookAfterMarketOrders(Currency base, Currency quote) private {
       console.log("Checking orderbook state after market orders...");
       
       // Market orders execute against existing limit orders, so:
       // 1. Some limit orders might be filled/removed
       // 2. Market orders themselves might be filled and removed
       // 3. Orderbook should still be in valid state
       
       IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
       IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);
       
       // If there are any orders left, they should be valid
       if (bestBuy.price > 0) {
           require(bestBuy.volume > 0, "BUY side has price but no volume");
       }
       
       if (bestSell.price > 0) {
           require(bestSell.volume > 0, "SELL side has price but no volume");
       }
       
       // If both sides exist, spread should be positive
       if (bestBuy.price > 0 && bestSell.price > 0) {
           require(bestSell.price > bestBuy.price, "Invalid spread after market orders");
       }
       
       // Verify placed market orders are in reasonable state
       for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
           IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, marketBuyOrderIds[i]);
           // Market orders should either be filled (and removed) or partially filled
           require(order.user == deployerAddress || order.id == 0, "Market order has wrong user or invalid state");
       }
       
       console.log("Orderbook state verification passed");
   }
}