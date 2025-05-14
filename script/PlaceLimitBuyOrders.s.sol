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

contract PlaceLimitBuyOrders is Script, DeployHelpers {
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

        placeLimitBuyOrders();

        verifyOrderBookState();

        vm.stopBroadcast();
    }

    function placeLimitBuyOrders() private {
        console.log("\n=== Placing Limit BUY Orders for ETH/USDC ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));

        // Get the pool using the resolver
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

        // Setup sender with funds - using a large amount to ensure we have enough
        _setupFunds(10e18, 1_000_000e6); // 10 ETH, 1,000,000 USDC

        // Place BUY orders (bids) - using higher prices (1900-1950) that are still below the SELL orders (2000+)
        // This ensures they won't get matched immediately but will provide liquidity for market SELL orders
        _placeBuyOrders(pool, 1900e6, 1950e6, 10e6, 5, 1e16);
        console.log("Placed 5 BUY orders from 1900 USDC to 1950 USDC");
        
        // Print summary
        console.log("ETH/USDC order book updated with:");
        console.log("- BUY orders from 1900 USDC to 1950 USDC");
    }

    function _setupFunds(uint256 ethAmount, uint256 usdcAmount) private {
        // Mint tokens directly to sender
        mockWETH.mint(msg.sender, ethAmount);
        mockUSDC.mint(msg.sender, usdcAmount);

        // Approve tokens for balance manager
        IERC20(address(mockWETH)).approve(address(balanceManager), ethAmount);
        IERC20(address(mockUSDC)).approve(address(balanceManager), usdcAmount);
        
        console.log("Minted and approved tokens:");
        console.log("- %s ETH", ethAmount / 1e18);
        console.log("- %s USDC", usdcAmount / 1e6);
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
            
            console.log("Placed limit BUY order ID: %s", orderId);
            console.log("- Price: %s USDC", currentPrice);
            console.log("- Quantity: %s ETH", quantity);

            currentPrice += priceStep;
            ordersPlaced++;
        }
    }

    function verifyOrderBookState() private {
        console.log("\n=== Verifying Order Book State After Placing Limit BUY Orders ===");
        
        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));
        
        // Check best prices on both sides
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        
        console.log("Best BUY price: %s USDC", bestBuy.price);
        console.log("Volume at best BUY: %s ETH", bestBuy.volume);
        
        console.log("Best SELL price: %s USDC", bestSell.price);
        console.log("Volume at best SELL: %s ETH", bestSell.volume);
        
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
        
        // Check a few specific price levels for BUY orders
        console.log("\nBUY side depth:");
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1950e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1940e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1930e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1920e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1910e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1900e6);
    }

    function _checkPriceLevel(Currency base, Currency quote, IOrderBook.Side side, uint128 price) private {
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(base, quote, side, price);
        string memory sideStr = side == IOrderBook.Side.BUY ? "BUY" : "SELL";

        console.log("Price level %s USDC - %s", price, sideStr);
        console.log("- Orders: %s", orderCount);
        console.log("- Volume: %s ETH", totalVolume);
    }
}
