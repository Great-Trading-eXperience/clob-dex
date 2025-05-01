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

contract FillMockOrderBook is Script, DeployHelpers {
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

        fillETHUSDCOrderBook();

        verifyOrders();

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

        // Place BUY orders (bids) - ascending price from 1900 to 1980
        _placeBuyOrders(pool, 1900e6, 1980e6, 10e6, 10, 5e17);

        // Place SELL orders (asks) - ascending price from 2000 to 2100
        _placeSellOrders(pool, 2000e6, 2100e6, 10e6, 10, 4e17);

        // Print summary
        console.log("ETH/USDC order book filled with:");
        console.log("- BUY orders from 1900 USDC to 1980 USDC");
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

    function verifyOrders() private {
        console.log("\n=== Verifying Order Book ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));

        // Get pool
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

        // Check best prices
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);

        console.log("Best BUY price:", bestBuy.price);
        console.log("USDC with volume:", bestBuy.volume, "ETH\n");

        console.log("Best SELL price:", bestSell.price);
        console.log("USDC with volume:", bestSell.volume, "ETH\n");

        // Check a few specific price levels
        _checkPriceLevel(weth, usdc, IOrderBook.Side.BUY, 1950e6);
        _checkPriceLevel(weth, usdc, IOrderBook.Side.SELL, 2050e6);

        // Check sample orders from both sides
        if (buyOrderIds.length > 0) {
            _checkOrderDetails(weth, usdc, buyOrderIds[0], "First BUY");
            _checkOrderDetails(weth, usdc, buyOrderIds[buyOrderIds.length - 1], "Last BUY");
        }

        if (sellOrderIds.length > 0) {
            _checkOrderDetails(weth, usdc, sellOrderIds[0], "First SELL");
            _checkOrderDetails(weth, usdc, sellOrderIds[sellOrderIds.length - 1], "Last SELL");
        }
    }

    function _checkPriceLevel(Currency base, Currency quote, IOrderBook.Side side, uint128 price) private {
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(base, quote, side, price);
        string memory sideStr = side == IOrderBook.Side.BUY ? "BUY" : "SELL";

        console.log("Price level", price, "USDC -", sideStr);
        console.log("orders:", orderCount);
        console.log("with volume:", totalVolume, "ETH");
        console.log("");
    }

    function _checkOrderDetails(Currency base, Currency quote, uint48 orderId, string memory label) private {
        IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, orderId);

        console.log("\nOrder details for", label);
        console.log("order (ID:", orderId, "):");
        console.log("User:", order.user);
        console.log("Order ID:", order.id);
        console.log("Side:", order.side == IOrderBook.Side.BUY ? "BUY" : "SELL");
        console.log("Type:", order.orderType == IOrderBook.OrderType.LIMIT ? "LIMIT" : "MARKET");
        console.log("Price:", order.price, "USDC");
        console.log("Quantity:", order.quantity, "ETH");
        console.log("Filled:", order.filled, "ETH");
        console.log("Next in queue:", order.next);
        console.log("Prev in queue:", order.prev);
        console.log("Status:", uint8(order.status));
        console.log("");
    }
}
