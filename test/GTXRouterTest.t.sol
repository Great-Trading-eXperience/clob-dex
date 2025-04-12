// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/mocks/MockToken.sol";
import "../src/OrderBook.sol";

contract GTXRouterTest is Test {
    GTXRouter private gtxRouter;
    PoolManager private poolManager;
    BalanceManager private balanceManager;
    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user = makeAddr("user");
    address private operator = address(0xABC);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    Currency private wbtc;
    Currency private weth;
    Currency private usdc;
    MockUSDC private mockUSDC;
    MockWETH private mockWETH;
    MockToken private mockWBTC;

    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 constant FEE_UNIT = 1000;

    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 10e6;
    uint256 private initialBalanceWETH = 1e18;

    // Default trading rules
    OrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        balanceManager = new BalanceManager(owner, feeReceiver, feeMaker, feeTaker);
        poolManager = new PoolManager(owner, address(balanceManager));
        gtxRouter = new GTXRouter(address(poolManager), address(balanceManager));

        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();
        mockWBTC = new MockToken("Mock WBTC", "mWBTC", 8);

        // Only mint to the user address in setup
        mockUSDC.mint(user, initialBalanceUSDC);
        mockWETH.mint(user, initialBalanceWETH);

        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));
        wbtc = Currency.wrap(address(mockWBTC));

        vm.deal(user, initialBalance);

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: Quantity.wrap(uint128(1e14)), // 0.0001 ETH,
            minAmountMovement: Quantity.wrap(uint128(1e14)), // 0.0001 ETH
            minOrderSize: Quantity.wrap(uint128(1e4)), // 0.01 USDC
            minPriceMovement: Quantity.wrap(uint128(1e4)), // 0.01 USDC with 6 decimals
            slippageTreshold: 20 // 20%
        });

        // Transfer ownership of BalanceManager to PoolManager
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(gtxRouter));
        poolManager.addCommonIntermediary(usdc);
        poolManager.createPool(weth, usdc, defaultTradingRules);
        poolManager.createPool(
            wbtc,
            usdc,
            IOrderBook.TradingRules({
                minTradeAmount: Quantity.wrap(uint128(1e3)), // 0.00001 BTC (8 decimals)
                minAmountMovement: Quantity.wrap(uint128(1e3)), // 0.00001 BTC (8 decimals)
                minOrderSize: Quantity.wrap(uint128(1e4)), // 0.01 USDC (6 decimals)
                minPriceMovement: Quantity.wrap(uint128(1e4)), // 0.01 USDC with 6 decimals 
                slippageTreshold: 20 // 20%
            })
        );
        vm.stopPrank();
    }

    function testPlaceOrderWithDeposit() public {
        uint256 depositAmount = 10 ether;
        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);

        PoolKey memory key = PoolKey(weth, usdc);
        // Price with 6 decimals (1 ETH = 3000 USDC)
        Price price = Price.wrap(3000 * 10 ** 6);
        // Quantity with 18 decimals (1 ETH)
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        Side side = Side.SELL;
        console.log("Setting side to SELL");

        OrderId orderId = gtxRouter.placeOrderWithDeposit(weth, usdc, price, quantity, side, alice);
        console.log("Order with deposit placed with ID:", OrderId.unwrap(orderId));

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);

        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        assertEq(orderCount, 1);
        assertEq(totalVolume, Quantity.unwrap(quantity));

        // Check the balance and locked balance from the balance manager
        uint256 balance = balanceManager.getBalance(user, weth);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(key).orderBook), weth);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testIgnoreMatchOrderSameTrader() public {
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        mockUSDC.mint(alice, initialBalanceUSDC);
        Price price = Price.wrap(uint64(1900e6));

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e18);
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, price, Quantity.wrap(uint128(1e18)), Side.SELL, alice
        );

        (uint256 balance, uint256 lockedBalance) = _getBalanceAndLockedBalance(
            alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth
        );

        assertEq(balance, 0, "Alice WETH balance should be 0 after placing sell order");
        assertEq(lockedBalance, 1e18, "Locked balance should be 1 ETH");

        // For BUY orders, we specify the base quantity (ETH) we want to buy
        // But we need to mint and approve the equivalent amount of USDC
        // 1 ETH at 1900 USDC/ETH = 1900 USDC
        mockUSDC.mint(alice, 1900e6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 1900e6);

        // Quantity for buy is in base asset (ETH)
        gtxRouter.placeOrderWithDeposit(weth, usdc, price, Quantity.wrap(1e18), Side.BUY, alice);

        vm.stopPrank();

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc
        );

        assertEq(balance, 0, "Alice USDC balance should be 0 after placing buy order");
        assertEq(lockedBalance, 1900e6, "Locked balance should be 1900 USDC");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth
        );

        assertEq(balance, 1e18, "Alice WETH balance should be 1 ETH");
        assertEq(lockedBalance, 0, "Locked balance should be 0 ETH");

        (uint48 orderCount, uint256 totalVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.SELL, price);
        assertEq(orderCount, 0, "Order count should be 0 after placing buy order");
        assertEq(totalVolume, 0, "Total volume should be 0 ETH after placing buy order");

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, Side.BUY, price);
        assertEq(orderCount, 1, "Order count should be 1 after placing buy order");
        assertEq(totalVolume, 1e18, "Total volume should be 1 ETH after placing buy order");
    }

    function _getBalanceAndLockedBalance(
        address user,
        address operator,
        Currency currency
    ) internal view returns (uint256 balance, uint256 lockedBalance) {
        balance = balanceManager.getBalance(user, currency);
        lockedBalance = balanceManager.getLockedBalance(user, operator, currency);
    }

    function testMatchBuyMarketOrder() public {
        // Set up a sell order

        vm.startPrank(alice);
        mockWETH.mint(alice, 1e17);
        assertEq(mockWETH.balanceOf(alice), 1e17, "Alice should have 0.1 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e17);

        address wethUsdcPair = address(poolManager.getPool(PoolKey(weth, usdc)).orderBook);

        // Place a sell order for 0.1 ETH at price of 1900 USDC
        Price sellPrice = Price.wrap(1900e6);
        Quantity sellQty = Quantity.wrap(1e17); // 0.1 ETH
        gtxRouter.placeOrderWithDeposit(weth, usdc, sellPrice, sellQty, Side.SELL, alice);
        vm.stopPrank();

        // Check the order was placed correctly
        (uint48 orderCount, uint256 totalVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.SELL, sellPrice);
        assertEq(orderCount, 1, "Should have 1 sell order");
        assertEq(totalVolume, 1e17, "Volume should be 0.1 ETH");

        uint256 balance = balanceManager.getBalance(alice, weth);
        uint256 lockedBalance = balanceManager.getLockedBalance(
            alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(alice, wethUsdcPair, weth);
        assertEq(balance, 0, "Alice WETH balance should be 0 after placing sell order");
        assertEq(lockedBalance, 1e17, "Locked balance should be 0.1 ETH");

        // Now place a series of market orders with increasing sizes

        // Test  market buy (0.0001 ETH)
        vm.startPrank(bob);
        // For 0.0001 ETH at price 1900 USDC/ETH, need 0.19 USDC
        mockUSDC.mint(bob, 19e4);
        assertEq(mockUSDC.balanceOf(bob), 19e4, "Bob should have 0.19 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 19e4);

        (balance, lockedBalance) = _getBalanceAndLockedBalance(bob, wethUsdcPair, usdc);
        assertEq(balance, 0, "Bob USDC balance should be 0 before market buy");
        assertEq(lockedBalance, 0, "Bob USDC locked balance should be 0 before market buy");

        // Quantity is in base asset (ETH) - 0.0001 ETH
        Quantity buyQty1 = Quantity.wrap(1e14);
        gtxRouter.placeMarketOrderWithDeposit(weth, usdc, buyQty1, Side.BUY, bob);
        vm.stopPrank();

        (balance, lockedBalance) = _getBalanceAndLockedBalance(bob, wethUsdcPair, usdc);
        assertEq(balance, 0, "Bob USDC balance should be 0 after market buy");
        assertEq(lockedBalance, 0, "Bob USDC locked balance should be 0 after market buy");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(bob, wethUsdcPair, weth);
        uint256 expectedEthReceived = 1e14; // 0.0001 ETH
        uint256 feeAmount = expectedEthReceived * 5 / 1000; // 0.0001 ETH * 0.5% (taker fee)
        assertEq(
            balance,
            expectedEthReceived - feeAmount,
            "Bob should receive 0.0001 ETH minus 0.5% taker fee"
        );
        assertEq(lockedBalance, 0, "Bob WETH locked balance should be 0 after market buy");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(alice, wethUsdcPair, usdc);
        uint256 expectedUsdcReceived = 0.19e6; // 0.0001 ETH * 1900 USDC per ETH
        feeAmount = expectedUsdcReceived * 1 / 1000; // 0.0001 ETH * 0.1% (maker fee)
        assertEq(
            balance,
            expectedUsdcReceived - feeAmount,
            "Alice should receive 0.0001 ETH minus 0.1% maker fee"
        );
        assertEq(lockedBalance, 0, "Alice USDC locked balance should be 0 after market buy");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(alice, wethUsdcPair, weth);
        assertEq(balance, 0, "Alice WETH balance should be 0 after market buy");
        assertEq(
            lockedBalance, 1e17 - 1e14, "Alice WETH locked balance should be 0 after market buy"
        );
    }

    function testMatchSellMarketOrder() public {
        // Set up a buy order
        vm.startPrank(alice);
        mockUSDC.mint(alice, 1900e6);
        assertEq(mockUSDC.balanceOf(alice), 1900e6, "Alice should have 1900 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 1900e6);

        // Place a buy order for 1 ETH at price of 1900 USDC
        Price buyPrice = Price.wrap(1900e6);

        // Quantity is in base units - 1 ETH
        Quantity buyQty = Quantity.wrap(1e18);
        gtxRouter.placeOrderWithDeposit(weth, usdc, buyPrice, buyQty, Side.BUY, alice);
        vm.stopPrank();

        // Check the order was placed correctly
        (uint48 orderCount, uint256 totalVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.BUY, buyPrice);
        assertEq(orderCount, 1, "Should have 1 buy order");

        // For buy orders placed through placeOrderWithDeposit, the volume is stored in quote units
        assertEq(totalVolume, 1e18, "Volume should be 1 ETH");

        // Now place a market sell order (selling ETH against the existing buy order)
        vm.startPrank(bob);
        mockWETH.mint(bob, 5e17); // 0.5 ETH
        assertEq(mockWETH.balanceOf(bob), 5e17, "Bob should have 0.5 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 5e17);

        // Sell 0.5 ETH as a market order
        Quantity sellQty = Quantity.wrap(5e17); // 0.5 ETH
        gtxRouter.placeMarketOrderWithDeposit(weth, usdc, sellQty, Side.SELL, bob);
        vm.stopPrank();

        // Check the state of the buy order after match
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, Side.BUY, buyPrice);
        assertEq(
            totalVolume, 1e18 - 5e17, "Remaining buy volume should be 0.5 ETH (half of original)"
        );
        assertEq(orderCount, 1, "Buy order should still exist with remaining quantity");

        (uint256 balance, uint256 lockedBalance) = _getBalanceAndLockedBalance(
            bob, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc
        );
        uint256 balanceAmount = 950e6;
        uint256 feeAmount = balanceAmount * 5 / 1000; // 0.5% fee on 1900 USDC
        assertEq(
            balance,
            balanceAmount - feeAmount,
            "Bob should receive 0.5 ETH worth of USDC minus 0.5% fee"
        );
        assertEq(lockedBalance, 0, "Bob USDC locked balance should be 0 after market sell");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            bob, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth
        );
        assertEq(balance, 0, "Bob WETH balance should be 0 after market sell");
        assertEq(lockedBalance, 0, "Bob WETH locked balance should be 0 ETH after market sell");

        // Alice WETH and USDC balance
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc
        );
        assertEq(balance, 0, "Alice USDC balance should be 0 after market sell");
        assertEq(
            lockedBalance, 950e6, "Alice USDC locked balance should be 950 USDC after market sell"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth
        );
        balanceAmount = 1e18 - 5e17;
        feeAmount = balanceAmount * 1 / 1000; // 0.1% fee on 0.5 ETH
        assertEq(
            balance,
            balanceAmount - feeAmount,
            "Alice WETH balance should be 0.5 ETH after market sell"
        );
        assertEq(lockedBalance, 0, "Alice WETH locked balance should be 0 ETH after market sell");

        vm.startPrank(charlie);
        mockWETH.mint(charlie, 5e17); // 0.5 ETH
        assertEq(mockWETH.balanceOf(charlie), 5e17, "Charlie should have 0.5 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 5e17);

        gtxRouter.placeMarketOrderWithDeposit(weth, usdc, Quantity.wrap(5e17), Side.SELL, charlie);
        vm.stopPrank();

        //Charlie WETH and USDC balance
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            charlie, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc
        );
        feeAmount = 950e6 * 5 / 1000; // 0.5% fee on 1900 USDC
        assertEq(
            balance, 950e6 - feeAmount, "Charlie USDC balance should be 950 USDC after market sell"
        );
        assertEq(lockedBalance, 0, "Charlie USDC locked balance should be 0 after market sell");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            charlie, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth
        );
        assertEq(balance, 0, "Charlie WETH balance should be 0 after market sell");
        assertEq(lockedBalance, 0, "Charlie WETH locked balance should be 0 ETH after market sell");

        // Check buy order should be fully matched now
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, Side.BUY, buyPrice);
        assertEq(orderCount, 0, "Buy order should be fully matched");
        assertEq(totalVolume, 0, "Buy volume should be 0 after full match");
    }

    function testLimitOrderMatching() public {
        // Mint tokens for the test
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        assertEq(
            mockWETH.balanceOf(alice), initialBalanceWETH, "Alice should have initial WETH balance"
        );

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        Price price = Price.wrap(2000e6);
        Quantity quantity = Quantity.wrap(1e18); // 1 ETH
        gtxRouter.placeOrderWithDeposit(weth, usdc, price, quantity, Side.SELL, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        mockUSDC.mint(bob, 2000e6); // Need enough for 1 ETH at 2000 USDC
        assertEq(mockUSDC.balanceOf(bob), 2000e6, "Bob should have 2000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 2000e6);
        // For buy orders, we're now using base quantity (ETH)
        Quantity buyQuantity = Quantity.wrap(1e18); // 1 ETH
        gtxRouter.placeOrderWithDeposit(weth, usdc, price, buyQuantity, Side.BUY, bob);
        vm.stopPrank();

        (uint48 orderCount, uint256 totalVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.SELL, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(orderCount, 0, "Sell order should be fully filled");
        assertEq(totalVolume, 0, "Total volume should be 0");
    }

    function testCancelOrder() public {
        // Create a fresh address for testing
        address trader = makeAddr("trader");

        // Mint WETH to the trader
        vm.startPrank(trader);
        mockWETH.mint(trader, 1 ether);

        // Approve WETH for the order
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1 ether);

        // Place a sell order
        Price price = Price.wrap(3000 * 10 ** 8); // 3000 USDC per ETH
        Quantity quantity = Quantity.wrap(0.1 * 10 ** 18); // 0.1 ETH
        Side side = Side.SELL;

        // Debug initial balances
        PoolKey memory key = PoolKey(weth, usdc);
        console.log("Initial balance:", balanceManager.getBalance(trader, weth));
        console.log(
            "Initial locked balance:",
            balanceManager.getLockedBalance(
                trader, address(poolManager.getPool(key).orderBook), weth
            )
        );

        // Place order with trader as both sender and beneficiary
        OrderId orderId = gtxRouter.placeOrderWithDeposit(weth, usdc, price, quantity, side, trader);

        // Debug post-order balances
        console.log("Balance after order:", balanceManager.getBalance(trader, weth));
        console.log(
            "Locked after order:",
            balanceManager.getLockedBalance(
                trader, address(poolManager.getPool(key).orderBook), weth
            )
        );

        // Verify order was placed
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 1, "Order should be placed");
        assertEq(totalVolume, Quantity.unwrap(quantity), "Volume should match quantity");

        // Cancel the order
        gtxRouter.cancelOrder(weth, usdc, side, price, orderId);

        // End the prank session here
        vm.stopPrank();

        // Debug post-cancellation balances
        uint256 balance = balanceManager.getBalance(trader, weth);
        uint256 lockedBalance = balanceManager.getLockedBalance(
            trader, address(poolManager.getPool(key).orderBook), weth
        );
        console.log("Balance after cancel:", balance);
        console.log("Locked after cancel:", lockedBalance);

        // Verify order was cancelled
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 0, "Order should be cancelled");
        assertEq(totalVolume, 0, "Volume should be 0 after cancellation");

        // Check the balance was released
        assertEq(lockedBalance, 0, "Locked balance should be 0 after cancellation");
        assertEq(
            balance, Quantity.unwrap(quantity), "Balance should be returned after cancellation"
        );
    }

    function testPartialMarketOrderMatching() public {
        // Setup sell order
        vm.startPrank(alice);
        mockWETH.mint(alice, 10e18);
        assertEq(mockWETH.balanceOf(alice), 10e18, "Alice should have 10 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10e18);
        Price sellPrice = Price.wrap(1000e6);
        Quantity sellQty = Quantity.wrap(10e18); // 10 ETH
        gtxRouter.placeOrderWithDeposit(weth, usdc, sellPrice, sellQty, Side.SELL, alice);
        vm.stopPrank();

        // Place partial market buy order
        vm.startPrank(bob);
        // Calculate required USDC for 6 ETH at 1000 USDC/ETH = 6000 USDC
        mockUSDC.mint(bob, 6000e6);
        assertEq(mockUSDC.balanceOf(bob), 6000e6, "Bob should have 6000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 6000e6);

        // Buy 6 ETH (base quantity)
        Quantity buyQty = Quantity.wrap(6e18); // 6 ETH
        gtxRouter.placeMarketOrderWithDeposit(weth, usdc, buyQty, Side.BUY, bob);
        vm.stopPrank();

        // Verify partial fill
        (uint48 orderCount, uint256 totalVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.SELL, sellPrice);
        console.log("Order Count after partial fill:", orderCount);
        console.log("Total Volume after partial fill:", totalVolume);

        assertEq(orderCount, 1, "Order should still exist");
        assertEq(totalVolume, 4e18, "Remaining volume should be 4 ETH");
    }

    function testGetBestPrice() public {
        // Set up sell orders at different price levels
        vm.startPrank(alice);
        mockWETH.mint(alice, 15e18); // Need 15 ETH for both orders
        assertEq(mockWETH.balanceOf(alice), 15e18, "Alice should have 15 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 15e18);
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), Quantity.wrap(10e18), Side.SELL, alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(900e6), Quantity.wrap(5e18), Side.SELL, alice
        );
        vm.stopPrank();

        OrderBook.PriceVolume memory bestPriceVolume = gtxRouter.getBestPrice(weth, usdc, Side.SELL);
        assertEq(Price.unwrap(bestPriceVolume.price), 900e6, "Best sell price should be 900");
    }

    function testGetNextBestPrices() public {
        // Set up sell orders at different price levels
        vm.startPrank(alice);
        mockWETH.mint(alice, 18e18); // Need 18 ETH for all orders
        assertEq(mockWETH.balanceOf(alice), 18e18, "Alice should have 18 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 18e18);
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), Quantity.wrap(10e18), Side.SELL, alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(900e6), Quantity.wrap(5e18), Side.SELL, alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(800e6), Quantity.wrap(3e18), Side.SELL, alice
        );
        vm.stopPrank();

        OrderBook.PriceVolume[] memory levels =
            gtxRouter.getNextBestPrices(weth, usdc, Side.SELL, Price.wrap(0), 3);

        assertEq(Price.unwrap(levels[0].price), 800e6);
        assertEq(levels[0].volume, 3e18);
        assertEq(Price.unwrap(levels[1].price), 900e6);
        assertEq(levels[1].volume, 5e18);
        assertEq(Price.unwrap(levels[2].price), 1000e6);
        assertEq(levels[2].volume, 10e18);
    }

    function testGetUserActiveOrders() public {
        // Set up orders for alice
        vm.startPrank(alice);
        mockWETH.mint(alice, 15e18); // Need 15 ETH for both orders
        assertEq(mockWETH.balanceOf(alice), 15e18, "Alice should have 15 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 15e18);
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), Quantity.wrap(10e18), Side.SELL, alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(900e6), Quantity.wrap(5e18), Side.SELL, alice
        );
        vm.stopPrank();

        OrderBook.Order[] memory aliceOrders = gtxRouter.getUserActiveOrders(weth, usdc, alice);
        assertEq(aliceOrders.length, 2, "Alice should have 2 active orders");
        assertEq(alice, aliceOrders[0].user);
        assertEq(alice, aliceOrders[1].user);
    }

    function testUnauthorizedCancellation() public {
        // Place an order for alice
        vm.startPrank(alice);
        mockWETH.mint(alice, 10e18);
        assertEq(mockWETH.balanceOf(alice), 10e18, "Alice should have 10 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10e18);
        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), Quantity.wrap(10e18), Side.SELL, alice
        );
        vm.stopPrank();

        // Try to cancel the order as bob
        vm.startPrank(bob);
        vm.expectRevert();
        gtxRouter.cancelOrder(weth, usdc, Side.SELL, Price.wrap(1000e6), orderId);
        vm.stopPrank();
    }

    function testOrderSizeValidation() public {
        vm.startPrank(alice);
        mockWETH.mint(alice, 2000e18); // Ensure enough balance for tests
        mockUSDC.mint(alice, 10_000e6); // Adding USDC for BUY tests
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2000e18);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10_000e6);

        // Get current trading rules for reference
        IOrderBook.TradingRules memory rules = defaultTradingRules;
        console.log("Min trade amount:", Quantity.unwrap(rules.minTradeAmount));
        console.log("Min order size:", Quantity.unwrap(rules.minOrderSize));
        console.log("Min amount movement:", Quantity.unwrap(rules.minAmountMovement));
        console.log("Min price movement:", Quantity.unwrap(rules.minPriceMovement));

        // Zero quantity
        Quantity zeroAmount = Quantity.wrap(0);
        vm.expectRevert(IBalanceManager.ZeroAmount.selector);
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), zeroAmount, Side.SELL, alice
        );

        vm.expectRevert(IBalanceManager.ZeroAmount.selector);
        gtxRouter.placeOrderWithDeposit(weth, usdc, Price.wrap(1000e6), zeroAmount, Side.BUY, alice);

        // Invalid price (zero)
        vm.expectRevert();
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(0), Quantity.wrap(10e18), Side.SELL, alice
        );

        // Order too small (SELL - base currency)
        Quantity tooSmallAmount = Quantity.wrap(1e13); // Smaller than min trade amount (1e14)
        vm.expectRevert(
            abi.encodeWithSelector(
                OrderBook.OrderTooSmall.selector,
                Quantity.unwrap(tooSmallAmount),
                Quantity.unwrap(rules.minTradeAmount)
            )
        );
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), tooSmallAmount, Side.SELL, alice
        );

        // Order too small (BUY - now in base units)
        Quantity tooSmallBuyAmount = Quantity.wrap(1e13);

        vm.expectRevert(
            abi.encodeWithSelector(
                OrderBook.OrderTooSmall.selector,
                Quantity.unwrap(tooSmallBuyAmount),
                Quantity.unwrap(rules.minTradeAmount)
            )
        );
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), tooSmallBuyAmount, Side.BUY, alice
        );

        // Invalid amount movement (SELL)
        // minAmountMovement is 1e14, so 1.00005e18 is not a multiple
        // Quantity invalidMovementAmount = Quantity.wrap(10_005e13);
        // vm.expectRevert(OrderBook.InvalidQuantityIncrement.selector);
        // gtxRouter.placeOrderWithDeposit(
        //     weth, usdc, Price.wrap(1000e6), invalidMovementAmount, Side.SELL, alice
        // );

        // Invalid price movement (BUY)
        // minPriceMovement is 1e4, so price of 1000.005e6 is not a valid increment
        vm.expectRevert(OrderBook.InvalidPriceIncrement.selector);
        gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1_000_005e3), Quantity.wrap(1e18), Side.BUY, alice
        );

        // Successful minimum valid order (SELL)
        Quantity minValidAmount = Quantity.wrap(1e14);
        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), minValidAmount, Side.SELL, alice
        );
        assertGt(OrderId.unwrap(orderId), 0, "Order should be placed successfully");

        // Successful minimum valid order (BUY)
        Quantity minValidBuyAmount = Quantity.wrap(1e14); 
        orderId = gtxRouter.placeOrderWithDeposit(
            weth, usdc, Price.wrap(1000e6), minValidBuyAmount, Side.BUY, alice
        );
        assertGt(OrderId.unwrap(orderId), 0, "Buy order should be placed successfully");

        vm.stopPrank();
    }

    function testMarketOrderWithNoLiquidity() public {
        vm.startPrank(bob);
        mockUSDC.mint(bob, initialBalanceUSDC);
        assertEq(
            mockUSDC.balanceOf(bob), initialBalanceUSDC, "Bob should have initial USDC balance"
        );

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);

        vm.expectRevert();
        gtxRouter.placeMarketOrderWithDeposit(weth, usdc, Quantity.wrap(10e18), Side.BUY, bob);

        vm.stopPrank();
    }

    function testOrderBookWithManyTraders() public {
        // Create 20 traders for testing
        address[] memory traders = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            traders[i] = address(uint160(i + 1000));

            // Mint tokens to each trader within their own prank context
            vm.startPrank(traders[i]);
            mockWETH.mint(traders[i], 100e18);
            mockUSDC.mint(traders[i], 200_000e6); // Increased USDC for buy orders
            assertEq(mockWETH.balanceOf(traders[i]), 100e18, "Trader should have 100 ETH");
            assertEq(mockUSDC.balanceOf(traders[i]), 200_000e6, "Trader should have 200,000 USDC");

            IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 100e18);
            IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 200_000e6);
            vm.stopPrank();
        }

        // Place buy orders at different price levels
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(traders[i]);
            uint64 price = uint64(1000e6 + i * 1e6); // Price in USDC per ETH

            // For buy orders, quantity is in base asset (ETH)
            Quantity buyQuantity = Quantity.wrap(5e18); // 5 ETH

            // Need to approve enough USDC for the buy: price * quantity
            uint256 usdcNeeded = (uint256(price) * 5e18) / 1e18;

            gtxRouter.placeOrderWithDeposit(
                weth, usdc, Price.wrap(price), buyQuantity, Side.BUY, traders[i]
            );
            vm.stopPrank();
        }

        // Place sell orders at different price levels
        for (uint256 i = 10; i < 20; i++) {
            vm.startPrank(traders[i]);
            gtxRouter.placeOrderWithDeposit(
                weth,
                usdc,
                Price.wrap(uint64(1050e6 + (i - 10) * 1e6)),
                Quantity.wrap(10e18), // Sell quantity in ETH
                Side.SELL,
                traders[i]
            );
            vm.stopPrank();
        }

        // Check some orders
        (uint48 buyOrderCount, uint256 buyVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.BUY, Price.wrap(1005e6));
        assertEq(buyOrderCount, 1, "Should have 1 buy order at price 1005");
        assertEq(buyVolume, 5e18, "Buy volume should be 5 ETH");

        (uint48 sellOrderCount, uint256 sellVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.SELL, Price.wrap(1055e6));
        assertEq(sellOrderCount, 1, "Should have 1 sell order at price 1055");
        assertEq(sellVolume, 10e18, "Sell volume should be 10e18");

        // Check order book depth
        OrderBook.PriceVolume[] memory buyLevels =
            gtxRouter.getNextBestPrices(weth, usdc, Side.BUY, Price.wrap(0), 5);
        assertEq(buyLevels.length, 5, "Should have 5 buy price levels");
        assertEq(Price.unwrap(buyLevels[0].price), 1009e6, "Best buy price should be 1009");

        OrderBook.PriceVolume[] memory sellLevels =
            gtxRouter.getNextBestPrices(weth, usdc, Side.SELL, Price.wrap(0), 5);
        assertEq(sellLevels.length, 5, "Should have 5 sell price levels");
        assertEq(Price.unwrap(sellLevels[0].price), 1050e6, "Best sell price should be 1050");

        // Now we'll add a market order to trigger some trades and check balances
        address marketTrader = makeAddr("marketTrader");
        vm.startPrank(marketTrader);
        mockUSDC.mint(marketTrader, 50_000e6); // Mint enough USDC for market buy
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 50_000e6);

        // Store initial balances of some sell traders before the trade
        address orderBookAddress = address(poolManager.getPool(PoolKey(weth, usdc)).orderBook);
        uint256 initialWethLocked10 =
            balanceManager.getLockedBalance(traders[10], orderBookAddress, weth);
        uint256 initialUsdcBalance10 = balanceManager.getBalance(traders[10], usdc);

        // Execute market buy that should match with lowest sell orders
        // Quantity is in base asset (ETH)
        Quantity marketBuyQty = Quantity.wrap(5e18); // Buy 5 ETH
        gtxRouter.placeMarketOrderWithDeposit(weth, usdc, marketBuyQty, Side.BUY, marketTrader);
        vm.stopPrank();

        // Verify balances after trade for the first sell trader (index 10)
        uint256 wethLockedAfter10 =
            balanceManager.getLockedBalance(traders[10], orderBookAddress, weth);
        uint256 usdcBalanceAfter10 = balanceManager.getBalance(traders[10], usdc);

        // Trader 10 should have sold ETH (reduced locked balance) and received USDC
        assertLt(
            wethLockedAfter10,
            initialWethLocked10,
            "Trader 10 should have less locked WETH after trade"
        );
        assertGt(
            usdcBalanceAfter10, initialUsdcBalance10, "Trader 10 should have more USDC after trade"
        );

        console.log("Trader 10 initial locked WETH:", initialWethLocked10);
        console.log("Trader 10 locked WETH after trade:", wethLockedAfter10);
        console.log("Trader 10 initial USDC balance:", initialUsdcBalance10);
        console.log("Trader 10 USDC balance after trade:", usdcBalanceAfter10);

        // Check market trader's balance after trade
        uint256 marketTraderEthBalance = balanceManager.getBalance(marketTrader, weth);
        uint256 marketTraderEthFee = (initialWethLocked10 - wethLockedAfter10) * 5 / 1000; // 0.5% taker fee
        uint256 expectedMarketTraderEthBalance =
            (initialWethLocked10 - wethLockedAfter10) - marketTraderEthFee;

        assertApproxEqAbs(
            marketTraderEthBalance,
            expectedMarketTraderEthBalance,
            1e14, // Allow for small rounding differences
            "Market trader should receive correct WETH amount minus fee"
        );
    }

    function testDirectSwap() public {
        // Setup a sell order for WETH-USDC
        vm.startPrank(alice);
        mockWETH.mint(alice, 10e18);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10e18);

        // Record Alice's initial balances (track balance in the BalanceManager)
        uint256 aliceWethBefore = balanceManager.getBalance(alice, weth);
        uint256 aliceUsdcBefore = balanceManager.getBalance(alice, usdc);

        Price sellPrice = Price.wrap(1000e6); // 1000 USDC per ETH
        Quantity sellQty = Quantity.wrap(10e18); // 10 ETH
        gtxRouter.placeOrderWithDeposit(weth, usdc, sellPrice, sellQty, Side.SELL, alice);
        vm.stopPrank();

        // Bob will perform the swap: USDC -> WETH
        vm.startPrank(bob);
        // Calculate USDC needed: 5 ETH * 1000 USDC/ETH = 5000 USDC
        mockUSDC.mint(bob, 5000e6); // 5000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 5000e6);

        // Quantity in base units (ETH) - we want to buy 5 ETH
        uint256 amountToSwap = 5e18;
        uint256 minReceived = 4.95e18; // Expect at least 4.95 ETH (with 0.5% taker fee)

        // Execute the swap - note we're passing ETH amount as the quantity
        uint256 received = gtxRouter.swap(
            usdc, // Source is USDC
            weth, // Target is WETH
            5000e6, // Amount of USDC to swap (5000 USDC)
            minReceived,
            2, // Max hops
            bob
        );

        vm.stopPrank();

        // Record final balances
        uint256 bobWethAfter = balanceManager.getBalance(bob, weth);
        uint256 bobUsdcAfter = balanceManager.getBalance(bob, usdc);
        
        assertEq(bobWethAfter, 0, "Bob should receive the returned amount");
        assertEq(bobUsdcAfter, 0, "Bob should have spent all USDC");
        assertEq(mockUSDC.balanceOf(bob), 0, "Bob should have spent all USDC");
        uint256 expectedReceived = 5e18 - (5e18 * 5 / 1000); // 5 ETH minus 0.5% taker fee
        assertEq(received, expectedReceived, "Swap should return correct ETH amount after fee");
        assertEq(mockWETH.balanceOf(bob), expectedReceived, "Bob should have received WETH");

        uint256 aliceUsdcAfter = balanceManager.getBalance(alice, usdc);
        uint256 expectedUsdcIncrease = 5000e6 - (5000e6 * 1 / 1000); // 5000 USDC minus 0.1% maker fee

        // Alice's ETH should decrease by 5 ETH (locked in order) - may need to check in balanceManager
        address orderBookAddress = address(poolManager.getPool(PoolKey(weth, usdc)).orderBook);
        uint256 aliceLockedWeth = balanceManager.getLockedBalance(alice, orderBookAddress, weth);
        assertEq(aliceLockedWeth, 5e18, "Alice should still have 5 ETH locked in remaining orders");

        // Alice's USDC should increase by expected amount (5000 USDC - 0.1% maker fee)
        assertEq(
            aliceUsdcAfter - aliceUsdcBefore,
            expectedUsdcIncrease,
            "Alice should receive USDC minus maker fee"
        );
    }

    function testMultiHopSwap() public {
        // Setup three pools: WETH/USDC, WBTC/USDC, and a direct WETH/WBTC pool

        // Setup WETH/USDC liquidity
        vm.startPrank(alice);
        mockWETH.mint(alice, 20e18);
        mockUSDC.mint(alice, 40_000e6);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 20e18);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 40_000e6);

        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(2000e6),
            Quantity.wrap(1e18), // 1 ETH (base quantity)
            Side.BUY,
            alice
        );

        // Check order was placed
        (uint48 orderCount, uint256 totalVolume) =
            gtxRouter.getOrderQueue(weth, usdc, Side.BUY, Price.wrap(2000e6));
        assertEq(orderCount, 1, "WETH/USDC BUY order should be placed");
        assertEq(totalVolume, 1e18, "WETH/USDC BUY volume should be 1 ETH");

        mockWBTC.mint(alice, 1e8);
        IERC20(Currency.unwrap(wbtc)).approve(address(balanceManager), 1e8);

        gtxRouter.placeOrderWithDeposit(
            wbtc, usdc, Price.wrap(30_000e6), Quantity.wrap(1e8), Side.SELL, alice
        );

        // Check order was placed
        (orderCount, totalVolume) =
            gtxRouter.getOrderQueue(wbtc, usdc, Side.SELL, Price.wrap(30_000e6));
        assertEq(orderCount, 1, "WBTC/USDC SELL order should be placed");
        assertEq(totalVolume, 1e8, "WBTC/USDC SELL volume should be 1 BTC");

        // Bob will now perform swaps to test both paths
        vm.startPrank(bob);
        mockWETH.mint(bob, 1e18); // Bob has 1 ETH to swap
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e18);

        // Multi-hop through USDC
        uint256 amountToSwap = 1e18; // 1 ETH
        uint256 minReceived = 6e6; // 0.06 BTC (lower than expected to account for fees)

        uint256 received = gtxRouter.swap(
            weth,
            wbtc,
            amountToSwap,
            minReceived,
            2, // Max 2 hops - allows multi-hop
            bob
        );

        console.log("WBTC received from first swap (should use multi-hop):", received);
        assertGt(received, 0, "Bob should receive WBTC from multi-hop swap");

        // Calculate the expected amount:
        // Step 1: ETH → USDC: 1 ETH at 2000 USDC/ETH minus 0.5% taker fee
        // 1 ETH * 2000 USDC/ETH = 2000 USDC
        // 2000 USDC - (2000 * 0.5%) = 2000 - 10 = 1990 USDC
        //
        // Step 2: USDC → WBTC: 1990 USDC at 30,000 USDC/WBTC minus 0.5% taker fee
        // 1990 USDC / 30,000 USDC/WBTC = 0.06633... WBTC
        // 0.06633... WBTC - (0.06633... * 0.5%) = 0.06600167 WBTC
        //
        // Final result: 0.06600167 WBTC (in WBTC's 8 decimal format = 6600167)
        uint256 expectedWbtc = 6_600_167; // 0.066 WBTC with 8 decimals
        assertEq(received, expectedWbtc, "WBTC amount should match the calculated value");

        vm.stopPrank();
    }
}
