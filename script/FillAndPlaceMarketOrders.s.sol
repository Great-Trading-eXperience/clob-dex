// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/PoolManager.sol";

import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/resolvers/PoolManagerResolver.sol";

contract FillAndPlaceMarketOrders is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    PoolManagerResolver poolManagerResolver;

    // Mock tokens
    MockWETH mockWETH;
    MockUSDC mockUSDC;

    // Track order IDs for verification
    uint48[] buyOrderIds;
    uint48[] sellOrderIds;
    uint48[] marketBuyOrderIds;
    uint48[] marketSellOrderIds;

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

        // Load mock tokens
        mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
        mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Fill the order book with limit orders
        fillETHUSDCOrderBook();

        // Step 2: Verify the order book state
        verifyOrderBookState();

        // Step 3: Place market orders
        placeMarketOrders();

        // Step 4: Verify market orders
        verifyMarketOrders();

        vm.stopBroadcast();
    }

    function fillETHUSDCOrderBook() private {
        console.log("\n=== Filling ETH/USDC Order Book ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));

        // Get the pool using the resolver
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

        // Setup sender with funds
        _setupFunds(200e18, 400_000e6); // 200 ETH, 400,000 USDC

        // Place BUY orders (bids) - ascending price from 1500 to 1800
        // Using lower prices to ensure they don't get matched immediately
        _placeBuyOrders(pool, 1500e6, 1800e6, 30e6, 10, 5e17);
        console.log("Placed 10 BUY orders from 1500 USDC to 1800 USDC");

        // Place SELL orders (asks) - ascending price from 2000 to 2100
        _placeSellOrders(pool, 2000e6, 2100e6, 10e6, 10, 4e17);
        console.log("Placed 10 SELL orders from 2000 USDC to 2100 USDC");
        
        // Print summary
        console.log("ETH/USDC order book filled with:");
        console.log("- BUY orders from 1500 USDC to 1800 USDC");
        console.log("- SELL orders from 2000 USDC to 2100 USDC");
    }

    function _setupFunds(uint256 ethAmount, uint256 usdcAmount) private {
        // Mint tokens directly to sender
        mockWETH.mint(msg.sender, ethAmount);
        mockUSDC.mint(msg.sender, usdcAmount);

        // Approve tokens for balance manager
        IERC20(address(mockWETH)).approve(address(balanceManager), ethAmount);
        IERC20(address(mockUSDC)).approve(address(balanceManager), usdcAmount);
    }

    function _placeBuyOrders(
        IPoolManager.Pool memory pool,
        uint128 startPrice,
        uint128 endPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 quantity
    ) private {
        uint128 currentPrice = startPrice;
        uint8 ordersPlaced = 0;

        while (currentPrice <= endPrice && ordersPlaced < numOrders) {
            uint48 orderId =
                gtxRouter.placeOrderWithDeposit(pool, currentPrice, quantity, IOrderBook.Side.BUY, msg.sender);
            buyOrderIds.push(orderId);

            currentPrice += priceStep;
            ordersPlaced++;
        }
    }

    function _placeSellOrders(
        IPoolManager.Pool memory pool,
        uint128 startPrice,
        uint128 endPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 quantity
    ) private {
        uint128 currentPrice = startPrice;
        uint8 ordersPlaced = 0;

        while (currentPrice <= endPrice && ordersPlaced < numOrders) {
            uint48 orderId =
                gtxRouter.placeOrderWithDeposit(pool, currentPrice, quantity, IOrderBook.Side.SELL, msg.sender);
            sellOrderIds.push(orderId);

            currentPrice += priceStep;
            ordersPlaced++;
        }
    }

    function verifyOrderBookState() private {
        console.log("\n=== Verifying Order Book State After Filling ===");
        
        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));
        
        // Check best prices on both sides
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        
        console.log("Best BUY price:", bestBuy.price, "USDC");
        console.log("Volume at best BUY:", bestBuy.volume, "ETH");
        
        console.log("Best SELL price:", bestSell.price, "USDC");
        console.log("Volume at best SELL:", bestSell.volume, "ETH");
        
        if (bestBuy.price == 0 || bestBuy.volume == 0) {
            console.log("WARNING: No BUY liquidity found! Market SELL orders will fail.");
        } else {
            console.log("[OK] BUY liquidity verified");
        }
        
        if (bestSell.price == 0 || bestSell.volume == 0) {
            console.log("WARNING: No SELL liquidity found! Market BUY orders will fail.");
        } else {
            console.log("[OK] SELL liquidity verified");
        }
        
        // Get next best prices to verify depth
        console.log("\n--- Order Book Depth ---");
        
        // Check a few specific price levels for BUY orders
        console.log("BUY side depth:");
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1800e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1650e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1500e6);
        
        // Check a few specific price levels for SELL orders
        console.log("SELL side depth:");
        _checkPriceLevel(weth, usdc, IOrderBook.Side.SELL, 2000e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.SELL, 2050e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.SELL, 2100e6);
    }

    function _checkPriceLevel(Currency base, Currency quote, IOrderBook.Side side, uint128 price) private {
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(base, quote, side, price);
        string memory sideStr = side == IOrderBook.Side.BUY ? "BUY" : "SELL";

        console.log("Price level", price, "USDC -", sideStr);
        console.log("orders:", orderCount);
        console.log("with volume:", totalVolume, "ETH");
        console.log("");
    }

    function placeMarketOrders() private {
        console.log("\n=== Placing Market Orders on ETH/USDC ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));

        // Get the pool using the resolver
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

        // Setup additional funds for market orders
        _setupAdditionalFunds(50e18, 500_000e6); // 50 ETH, 500,000 USDC

        // Check for liquidity in the order book before placing market orders
        console.log("\n=== Checking Order Book Liquidity Before Market Orders ===");
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        
        console.log("Best BUY price:", bestBuy.price, "USDC");
        console.log("Volume at best BUY:", bestBuy.volume, "ETH");
        console.log("Best SELL price:", bestSell.price, "USDC");
        console.log("Volume at best SELL:", bestSell.volume, "ETH");
        
        if (bestBuy.price == 0 || bestBuy.volume == 0) {
            console.log("WARNING: No BUY liquidity found! Market SELL orders will fail.");
        }
        
        if (bestSell.price == 0 || bestSell.volume == 0) {
            console.log("WARNING: No SELL liquidity found! Market BUY orders will fail.");
        }
        
        // Print current allowances
        console.log("\nCurrent allowances:");
        console.log("WETH allowance:", IERC20(address(mockWETH)).allowance(msg.sender, address(balanceManager)));
        console.log("USDC allowance:", IERC20(address(mockUSDC)).allowance(msg.sender, address(balanceManager)));
        
        // Place market BUY orders (buys ETH with USDC)
        console.log("\n--- Placing Market BUY Orders ---");
        _placeMarketBuyOrders(pool, 1); // 1 buy order
        
        // Check for BUY liquidity before placing market SELL orders
        console.log("\n--- Checking for BUY Liquidity Before Market SELL Orders ---");
        IOrderBook.PriceVolume memory bestBuyBeforeSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        console.log("Best BUY price before SELL orders:", bestBuyBeforeSell.price, "USDC");
        console.log("Volume at best BUY:", bestBuyBeforeSell.volume, "ETH");
        
        if (bestBuyBeforeSell.price == 0 || bestBuyBeforeSell.volume == 0) {
            console.log("ERROR: No BUY liquidity found! Market SELL orders will fail.");
        } else {
            console.log("[OK] BUY liquidity verified");
            
            // Place market SELL orders (sells ETH for USDC)
            console.log("\n--- Placing Market SELL Orders ---");
            _placeMarketSellOrders(pool, 1); // 1 sell order
        }
    }

    function _setupAdditionalFunds(uint256 ethAmount, uint256 usdcAmount) private {
        // Mint additional tokens directly to sender
        mockWETH.mint(msg.sender, ethAmount);
        mockUSDC.mint(msg.sender, usdcAmount);
    }

    function _placeMarketBuyOrders(
        IPoolManager.Pool memory pool,
        uint8 numOrders
    ) private {
        for (uint8 i = 0; i < numOrders; i++) {
            // Create a market BUY order for 0.001 ETH
            uint48 orderId = gtxRouter.placeMarketOrderWithDeposit(
                pool,
                1e15, // 0.001 ETH
                IOrderBook.Side.BUY,
                msg.sender
            );
            
            marketBuyOrderIds.push(orderId);
            console.log("Placed market BUY order ID:", orderId);
            console.log("Quantity:", 1e15, "ETH");
        }
    }

    function _placeMarketSellOrders(
        IPoolManager.Pool memory pool,
        uint8 numOrders
    ) private {
        for (uint8 i = 0; i < numOrders; i++) {
            // Create a market SELL order for 0.001 ETH
            uint48 orderId = gtxRouter.placeMarketOrderWithDeposit(
                pool,
                1e15, // 0.001 ETH
                IOrderBook.Side.SELL,
                msg.sender
            );
            
            marketSellOrderIds.push(orderId);
            console.log("Placed market SELL order ID:", orderId);
            console.log("Quantity:", 1e15, "ETH");
        }
    }

    function verifyMarketOrders() private {
        console.log("\n=== Verifying Market Orders ===");
        
        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));
        
        // Check market BUY orders
        console.log("\n--- Market BUY Orders ---");
        for (uint8 i = 0; i < marketBuyOrderIds.length; i++) {
            _checkOrderDetails(weth, usdc, marketBuyOrderIds[i], string.concat("Market BUY #", _uint2str(i + 1)));
        }
        
        // Check market SELL orders
        console.log("\n--- Market SELL Orders ---");
        for (uint8 i = 0; i < marketSellOrderIds.length; i++) {
            _checkOrderDetails(weth, usdc, marketSellOrderIds[i], string.concat("Market SELL #", _uint2str(i + 1)));
        }
        
        // Check order book state after market orders
        console.log("\n--- Order Book State After Market Orders ---");
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        
        console.log("Best BUY price:", bestBuy.price, "USDC");
        console.log("Volume at best BUY:", bestBuy.volume, "ETH");
        console.log("\nBest SELL price:", bestSell.price, "USDC");
        console.log("Volume at best SELL:", bestSell.volume, "ETH");
        
        // Check balances
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
        console.log("Sender ETH balance:", mockWETH.balanceOf(msg.sender), "wei");
        console.log("Sender USDC balance:", mockUSDC.balanceOf(msg.sender), "units");
        console.log("BalanceManager ETH balance:", mockWETH.balanceOf(address(balanceManager)), "wei");
        console.log("BalanceManager USDC balance:", mockUSDC.balanceOf(address(balanceManager)), "units");
    }

    function _uint2str(uint v) private pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = bytes1(uint8(48 + remainder));
        }
        
        bytes memory s = new bytes(i);
        for (uint j = 0; j < i; j++) {
            s[j] = reversed[i - j - 1];
        }
        
        return string(s);
    }
}
