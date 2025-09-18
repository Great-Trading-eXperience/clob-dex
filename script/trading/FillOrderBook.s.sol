// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/GTXRouter.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/libraries/Pool.sol";

import "../../src/core/resolvers/PoolManagerResolver.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockWETH.sol";

contract FillMockOrderBook is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "BalanceManager";
    string constant POOL_MANAGER_ADDRESS = "PoolManager";
    string constant GTX_ROUTER_ADDRESS = "GTXRouter";
    string constant WETH_ADDRESS = "gsWETH";
    string constant USDC_ADDRESS = "gsUSDC";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    PoolManagerResolver poolManagerResolver;

    // Tokens
    IERC20 tokenWETH;
    IERC20 tokenUSDC;

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
        // Load core contracts - try new naming first, fallback to old naming
        address bmAddr = deployed["PROXY_BALANCEMANAGER"].isSet ? deployed["PROXY_BALANCEMANAGER"].addr : deployed[BALANCE_MANAGER_ADDRESS].addr;
        address pmAddr = deployed["PROXY_POOLMANAGER"].isSet ? deployed["PROXY_POOLMANAGER"].addr : deployed[POOL_MANAGER_ADDRESS].addr;
        address routerAddr = deployed["PROXY_ROUTER"].isSet ? deployed["PROXY_ROUTER"].addr : deployed[GTX_ROUTER_ADDRESS].addr;
        
        balanceManager = BalanceManager(bmAddr);
        poolManager = PoolManager(pmAddr);
        gtxRouter = GTXRouter(routerAddr);

        // Load tokens
        tokenWETH = IERC20(deployed[WETH_ADDRESS].addr);
        tokenUSDC = IERC20(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        fillETHUSDCOrderBook();

        verifyOrders();

        checkOrderBookDepth();

        vm.stopBroadcast();
    }

    function runConfigurable(
        uint128 buyStartPrice,
        uint128 buyEndPrice,
        uint128 sellStartPrice,
        uint128 sellEndPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 buyQuantity,
        uint128 sellQuantity,
        uint256 ethAmount,
        uint256 usdcAmount
    ) public {
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        fillETHUSDCOrderBookConfigurable(
            buyStartPrice,
            buyEndPrice,
            sellStartPrice,
            sellEndPrice,
            priceStep,
            numOrders,
            buyQuantity,
            sellQuantity,
            ethAmount,
            usdcAmount
        );

        verifyOrders();

        checkOrderBookDepth();

        vm.stopBroadcast();
    }

    function fillETHUSDCOrderBook() private {
        console.log("\n=== Filling ETH/USDC Order Book ===");

        // Get synthetic tokens for trading 
        address gsWETH = deployed["gsWETH"].addr;
        address gsUSDC = deployed["gsUSDC"].addr;
        
        Currency synthWeth = Currency.wrap(gsWETH);
        Currency synthUsdc = Currency.wrap(gsUSDC);

        // Create PoolKey and check if pool exists
        PoolKey memory poolKey = poolManager.createPoolKey(synthWeth, synthUsdc);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
        
        console.log("Pool baseCurrency:", Currency.unwrap(pool.baseCurrency));
        console.log("Pool quoteCurrency:", Currency.unwrap(pool.quoteCurrency));

        // Setup sender with funds and make local deposits for BalanceManager
        // _setupFunds(200e18, 400_000e6); // 200 ETH, 400,000 USDC
        // _makeLocalDeposits(100e18, 500_000e6); // Deposit 100 ETH, 500,000 USDC to BalanceManager

        // Place BUY orders (bids) - ascending price from 1900 to 1980
        // Increase order size to 0.01 ETH to meet minimum requirements
        _placeBuyOrders(pool, 1900e6, 1980e6, 10e6, 10, 1e16);

        console.log("Skipping SELL orders due to balance calculation issue - BUY orders successfully created!");

        // Print summary
        console.log("ETH/USDC order book filled with:");
        console.log("- BUY orders from 1900 USDC to 1980 USDC");
        console.log("- SELL orders: SKIPPED due to balance overflow issue");
    }

    function fillETHUSDCOrderBookConfigurable(
        uint128 buyStartPrice,
        uint128 buyEndPrice,
        uint128 sellStartPrice,
        uint128 sellEndPrice,
        uint128 priceStep,
        uint8 numOrders,
        uint128 buyQuantity,
        uint128 sellQuantity,
        uint256 ethAmount,
        uint256 usdcAmount
    ) private {
        console.log("\n=== Filling ETH/USDC Order Book (Configurable) ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(tokenWETH));
        Currency usdc = Currency.wrap(address(tokenUSDC));

        // Create PoolKey and get the pool (back to original order)
        PoolKey memory poolKey = poolManager.createPoolKey(usdc, weth);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

        // Setup sender with configurable funds
        _setupFunds(ethAmount, usdcAmount);

        // Place BUY orders (bids) with configurable parameters
        _placeBuyOrders(pool, buyStartPrice, buyEndPrice, priceStep, numOrders, buyQuantity);

        // Place SELL orders (asks) with configurable parameters
        _placeSellOrders(pool, sellStartPrice, sellEndPrice, priceStep, numOrders, sellQuantity);

        // Print summary
        console.log("ETH/USDC order book filled with:");
        console.log("- BUY orders from %s to %s USDC", buyStartPrice, buyEndPrice);
        console.log("- SELL orders from %s to %s USDC", sellStartPrice, sellEndPrice);
    }

    function runWithTokens(string memory token0Key, string memory token1Key) public {
        loadDeployments();

        // Load token addresses from deployment file
        address token0Address = deployed[token0Key].addr;
        address token1Address = deployed[token1Key].addr;

        require(token0Address != address(0), string(abi.encodePacked("Token not found: ", token0Key)));
        require(token1Address != address(0), string(abi.encodePacked("Token not found: ", token1Key)));

        console.log("Using tokens:");
        console.log("Token0 (%s):", token0Key, token0Address);
        console.log("Token1 (%s):", token1Key, token1Address);

        // Load core contracts
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);

        // Use the provided tokens instead of hardcoded ones
        tokenWETH = MockWETH(payable(token0Address));
        tokenUSDC = MockUSDC(token1Address);

        // Deploy the resolver
        poolManagerResolver = new PoolManagerResolver();

        // Get currency objects
        Currency weth = Currency.wrap(address(tokenWETH));
        Currency usdc = Currency.wrap(address(tokenUSDC));

        // Create PoolKey and get the pool (back to original order)
        PoolKey memory poolKey = poolManager.createPoolKey(usdc, weth);
        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);

        // Setup sender with funds and make local deposits for BalanceManager
        // _setupFunds(200e18, 400_000e6); // 200 ETH, 400,000 USDC
        // _makeLocalDeposits(100e18, 500_000e6); // Deposit 100 ETH, 500,000 USDC to BalanceManager

        // Place BUY orders (bids) - ascending price from 1900 to 1980
        _placeBuyOrders(pool, 1900e6, 1980e6, 10e6, 10, 1e15);

        // Place SELL orders (asks) - ascending price from 2000 to 2100
        _placeSellOrders(pool, 2000e6, 2100e6, 10e6, 10, 1e15);

        console.log("Order book filled with custom tokens:");
        console.log("Token0 (%s):", token0Key, token0Address);
        console.log("Token1 (%s):", token1Key, token1Address);
    }

    function _setupFunds(uint256 ethAmount, uint256 usdcAmount) private {
        console.log("\n=== Setting up funds ===");
        console.log("Minting ETH amount:", ethAmount, "(raw)");
        console.log("Minting ETH amount:", ethAmount / 1e18, "ETH");
        console.log("Minting USDC amount:", usdcAmount, "(raw)");
        console.log("Minting USDC amount:", usdcAmount / 1e6, "USDC");

        // Check if tokens support minting (have mint function)
        try MockWETH(payable(address(tokenWETH))).mint(msg.sender, ethAmount) {
            console.log("Minted WETH successfully");
        } catch {
            console.log("WETH minting failed - using existing supply");
        }
        
        try MockUSDC(address(tokenUSDC)).mint(msg.sender, usdcAmount) {
            console.log("Minted USDC successfully");  
        } catch {
            console.log("USDC minting failed - using existing supply");
        }

        // Approve tokens for both GTX router and BalanceManager (higher amounts for multiple orders)
        bool wethApprovalRouter = IERC20(address(tokenWETH)).approve(address(gtxRouter), ethAmount * 2);
        bool usdcApprovalRouter = IERC20(address(tokenUSDC)).approve(address(gtxRouter), usdcAmount * 2);
        bool wethApprovalBM = IERC20(address(tokenWETH)).approve(address(balanceManager), ethAmount * 2);
        bool usdcApprovalBM = IERC20(address(tokenUSDC)).approve(address(balanceManager), usdcAmount * 2);

        console.log("WETH approval (router):", wethApprovalRouter);
        console.log("USDC approval (router):", usdcApprovalRouter);
        console.log("WETH approval (BalanceManager):", wethApprovalBM);
        console.log("USDC approval (BalanceManager):", usdcApprovalBM);

        // Verify final balances and allowances
        console.log("Final WETH balance:", tokenWETH.balanceOf(msg.sender) / 1e18, "ETH");
        console.log("Final USDC balance:", tokenUSDC.balanceOf(msg.sender) / 1e6, "USDC");
        console.log(
            "Final WETH allowance:",
            IERC20(address(tokenWETH)).allowance(msg.sender, address(gtxRouter)) / 1e18,
            "ETH"
        );
        console.log(
            "Final USDC allowance:",
            IERC20(address(tokenUSDC)).allowance(msg.sender, address(gtxRouter)) / 1e6,
            "USDC"
        );
        console.log("Funds setup complete\n");
    }

    function _makeLocalDeposits(uint256 ethAmount, uint256 usdcAmount) private {
        console.log("\n=== Making Local Deposits to BalanceManager ===");
        console.log("Depositing ETH amount:", ethAmount / 1e18, "ETH");
        console.log("Depositing USDC amount:", usdcAmount / 1e6, "USDC");
        
        // Deposit real WETH to BalanceManager (will receive synthetic balance)
        balanceManager.depositLocal(address(tokenWETH), ethAmount, msg.sender);
        console.log("[SUCCESS] WETH deposited to BalanceManager");
        
        // Deposit real USDC to BalanceManager (will receive synthetic balance)
        balanceManager.depositLocal(address(tokenUSDC), usdcAmount, msg.sender);
        console.log("[SUCCESS] USDC deposited to BalanceManager");
        
        // Verify BalanceManager balances for the deposited tokens
        uint256 wethBalance = balanceManager.getBalance(msg.sender, Currency.wrap(address(tokenWETH)));
        uint256 usdcBalance = balanceManager.getBalance(msg.sender, Currency.wrap(address(tokenUSDC)));
        
        console.log("BalanceManager WETH balance:", wethBalance / 1e18, "ETH");
        console.log("BalanceManager USDC balance:", usdcBalance / 1e6, "USDC");
        
        // Also check synthetic balances (might be 0 if not mapped)
        address gsWETH = deployed["gsWETH"].addr;
        address gsUSDC = deployed["gsUSDC"].addr;
        uint256 syntheticWethBalance = balanceManager.getBalance(msg.sender, Currency.wrap(gsWETH));
        uint256 syntheticUsdcBalance = balanceManager.getBalance(msg.sender, Currency.wrap(gsUSDC));
        
        console.log("BalanceManager gsWETH balance:", syntheticWethBalance / 1e18, "ETH");
        console.log("BalanceManager gsUSDC balance:", syntheticUsdcBalance / 1e6, "USDC");
        console.log("Local deposits complete\n");
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
            console.log("\n--- Placing BUY Order #", ordersPlaced + 1, "---");
            console.log("Price:", currentPrice, "(raw)");
            console.log("Price (USDC):", currentPrice / 1e6);
            console.log("Quantity:", quantity, "(raw)");
            console.log("Quantity (ETH):", quantity / 1e18);

            // Calculate required deposit for buy order: price * quantity (in USDC)
            // This should give us the USDC amount needed (in USDC's 6 decimals)
            uint128 requiredDeposit = (currentPrice * quantity) / 1e18;

            console.log("Calculated deposit:", requiredDeposit, "(raw)");
            console.log("Calculated deposit (USDC):", requiredDeposit / 1e6);

            // Check user balances before placing order
            uint256 usdcBalance = tokenUSDC.balanceOf(msg.sender);
            uint256 usdcAllowance = IERC20(address(tokenUSDC)).allowance(msg.sender, address(gtxRouter));

            console.log("User USDC balance:", usdcBalance, "(raw)");
            console.log("User USDC balance:", usdcBalance / 1e6, "USDC");
            console.log("USDC allowance:", usdcAllowance, "(raw)");
            console.log("USDC allowance:", usdcAllowance / 1e6, "USDC");

            console.log("Placing limit order...");
            uint48 orderId = gtxRouter.placeLimitOrder(
                pool, currentPrice, quantity, IOrderBook.Side.BUY, IOrderBook.TimeInForce.GTC, 0
            );

            console.log("Order placed successfully! Order ID:", orderId);
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
            console.log("\n--- Placing SELL Order #", ordersPlaced + 1, "---");
            console.log("Price:", currentPrice, "(raw)");
            console.log("Price (USDC):", currentPrice / 1e6);
            console.log("Quantity:", quantity, "(raw)");
            console.log("Quantity (ETH):", quantity / 1e18);

            // For sell orders, deposit the base currency (WETH) quantity
            uint128 requiredDeposit = quantity;

            console.log("Required deposit:", requiredDeposit, "(raw)");
            console.log("Required deposit (ETH):", requiredDeposit / 1e18);

            // Check user balances before placing order
            uint256 wethBalance = tokenWETH.balanceOf(msg.sender);
            uint256 wethAllowance = IERC20(address(tokenWETH)).allowance(msg.sender, address(gtxRouter));

            console.log("User WETH balance:", wethBalance, "(raw)");
            console.log("User WETH balance:", wethBalance / 1e18, "ETH");
            console.log("WETH allowance:", wethAllowance, "(raw)");
            console.log("WETH allowance:", wethAllowance / 1e18, "ETH");

            console.log("Placing limit order...");
            uint48 orderId = gtxRouter.placeLimitOrder(
                pool, currentPrice, quantity, IOrderBook.Side.SELL, IOrderBook.TimeInForce.GTC, 0
            );

            console.log("Order placed successfully! Order ID:", orderId);
            sellOrderIds.push(orderId);

            currentPrice += priceStep;
            ordersPlaced++;
        }
    }

    function verifyOrders() private {
        console.log("\n=== Verifying Order Book ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(tokenWETH));
        Currency usdc = Currency.wrap(address(tokenUSDC));

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

    function checkOrderBookDepth() private {
        console.log("\n=== Verifying OrderBook State ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(tokenWETH));
        Currency usdc = Currency.wrap(address(tokenUSDC));

        // Verify BUY orders are correctly placed
        _verifyBuyOrdersPlaced(weth, usdc);

        // Verify SELL orders are correctly placed (if any)
        _verifySellOrdersPlaced(weth, usdc);

        // Verify orderbook structure is correct
        _verifyOrderBookStructure(weth, usdc);

        console.log("All orderbook verifications passed!");
    }

    function _verifyBuyOrdersPlaced(Currency base, Currency quote) private {
        console.log("Checking BUY orders...");

        // Verify we have buy orders placed
        require(buyOrderIds.length > 0, "No BUY orders were placed");

        // Check best BUY price exists
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
        require(bestBuy.price > 0, "No best BUY price found");
        require(bestBuy.volume > 0, "No volume at best BUY price");

        // Verify each placed order exists and has valid data
        for (uint256 i = 0; i < buyOrderIds.length; i++) {
            IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, buyOrderIds[i]);
            require(order.id == buyOrderIds[i], "Order ID mismatch");
            require(order.user == msg.sender, "Order user mismatch");
            require(order.side == IOrderBook.Side.BUY, "Order side mismatch");
            require(order.price > 0, "Invalid order price");

            // Check that there's still some volume at this price level (may be partially filled)
            (uint48 orderCount, uint256 totalVolume) =
                gtxRouter.getOrderQueue(base, quote, IOrderBook.Side.BUY, order.price);
            require(orderCount > 0, string(abi.encodePacked("No orders at price ", uint2str(order.price))));
            require(totalVolume > 0, string(abi.encodePacked("No volume at price ", uint2str(order.price))));
        }

        console.log("BUY orders verification passed");
    }

    function _verifySellOrdersPlaced(Currency base, Currency quote) private {
        console.log("Checking SELL orders...");

        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);

        if (sellOrderIds.length == 0) {
            console.log("No SELL orders placed");
        } else {
            // If SELL orders exist, verify they're correctly placed
            require(bestSell.price > 0, "SELL orders placed but no best price");
            require(bestSell.volume > 0, "SELL orders placed but no volume");

            // Verify each placed sell order exists and has valid data
            for (uint256 i = 0; i < sellOrderIds.length; i++) {
                IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, sellOrderIds[i]);
                require(order.id == sellOrderIds[i], "SELL order ID mismatch");
                require(order.user == msg.sender, "SELL order user mismatch");
                require(order.side == IOrderBook.Side.SELL, "SELL order side mismatch");
                require(order.price > 0, "Invalid SELL order price");

                // Check that there's still some volume at this price level (may be partially filled)
                (uint48 orderCount, uint256 totalVolume) =
                    gtxRouter.getOrderQueue(base, quote, IOrderBook.Side.SELL, order.price);
                require(orderCount > 0, string(abi.encodePacked("No SELL orders at price ", uint2str(order.price))));
                require(totalVolume > 0, string(abi.encodePacked("No SELL volume at price ", uint2str(order.price))));
            }

            console.log("SELL orders verification passed");
        }
    }

    function _verifyOrderBookStructure(Currency base, Currency quote) private {
        console.log("Checking orderbook structure...");

        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(base, quote, IOrderBook.Side.SELL);

        // Verify BUY side exists
        require(bestBuy.price > 0, "No BUY orders in orderbook");
        require(bestBuy.volume > 0, "No BUY volume in orderbook");

        // If both sides exist, verify spread is positive
        if (bestSell.price > 0) {
            require(bestSell.price > bestBuy.price, "Invalid spread: ask <= bid");
            console.log("Valid bid-ask spread");
        }

        // Verify order IDs are valid and orders exist
        for (uint256 i = 0; i < buyOrderIds.length; i++) {
            IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, buyOrderIds[i]);
            require(order.id == buyOrderIds[i], "Order ID mismatch");
            require(order.user == msg.sender, "Order user mismatch");
            require(order.side == IOrderBook.Side.BUY, "Order side mismatch");
            require(order.quantity > 0, "Invalid order quantity");
        }

        console.log("Orderbook structure verification passed");
    }

    // Utility function to convert uint to string
    function uint2str(
        uint256 _i
    ) internal pure returns (string memory str) {
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
}
