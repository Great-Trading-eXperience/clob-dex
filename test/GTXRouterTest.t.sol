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
import {IOrderBookErrors} from "../src/interfaces/IOrderBookErrors.sol";

contract GTXRouterTest is Test {
    GTXRouter private gtxRouter;
    PoolManager private poolManager;
    BalanceManager private balanceManager;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private user = address(0x3);
    address private operator = address(0x4);

    address alice = address(0x5);
    address bob = address(0x6);
    address charlie = address(0x7);

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
        balanceManager = new BalanceManager(
            owner,
            feeReceiver,
            feeMaker,
            feeTaker
        );
        poolManager = new PoolManager(owner, address(balanceManager));
        gtxRouter = new GTXRouter(
            address(poolManager),
            address(balanceManager)
        );

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

    function testValidateCallerBalanceForBuyOrder() public {
        // First add some sell orders to create liquidity on the sell side
        vm.startPrank(user);
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            10 ether
        );
        balanceManager.deposit(weth, 10 ether, user, user);

        // Place a sell order to create liquidity (1 ETH at 3000 USDC)
        Price sellPrice = Price.wrap(3000 * 10 ** 6); // 3000 USDC per ETH
        Quantity sellQty = Quantity.wrap(1 * 10 ** 18); // 1 ETH
        gtxRouter.placeOrder(weth, usdc, sellPrice, sellQty, Side.SELL, user);
        vm.stopPrank();

        // Now test buyer validation
        vm.startPrank(bob);
        // Mint USDC to bob
        mockUSDC.mint(bob, 5000 * 10 ** 6); // 5000 USDC

        // Approve USDC to be spent
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            5000 * 10 ** 6
        );

        // Prepare for a BUY order of 0.5 ETH
        Quantity buyQty = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH

        // Test 1: Successful validation when sufficient balance exists (direct deposit)
        OrderId orderId;
        try
            gtxRouter.placeOrderWithDeposit(
                weth,
                usdc,
                Price.wrap(3100 * 10 ** 6),
                buyQty,
                Side.BUY,
                bob
            )
        returns (OrderId returnedOrderId) {
            orderId = returnedOrderId;
            console.log(
                "Buy order placed successfully with ID:",
                OrderId.unwrap(orderId)
            );

            // Verify locked balances
            PoolKey memory poolKey = poolManager.createPoolKey(weth, usdc);
            IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
            uint256 balanceWETH = balanceManager.getBalance(
                bob,
                weth // Use Currency type instead of MockWETH
            );

            // Calculate expected amount: 0.5 ETH * 3100 USDC/ETH = 1550 USDC
            // First calculate the base amount (0.5 ETH)
            uint256 baseAmount = 5 * 10 ** 17; // 0.5 ETH
            // Apply taker fee (0.5%)
            uint256 expectedBalance = (baseAmount * (FEE_UNIT - feeTaker)) /
                FEE_UNIT;
            console.log("Expected balance:", expectedBalance);

            assertEq(
                balanceWETH,
                expectedBalance,
                "WETH balance should match the order amount"
            );
        } catch Error(string memory reason) {
            console.log(
                string.concat(
                    "Buy order validation failed unexpectedly: ",
                    reason
                )
            );
            assertTrue(false, "Buy order validation failed");
        }

        vm.stopPrank();

        // Test 2: Insufficient balance validation
        address poorUser = makeAddr("poorUser");
        vm.startPrank(poorUser);
        mockUSDC.mint(poorUser, 100 * 10 ** 6); // Only 100 USDC, not enough for the order
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            100 * 10 ** 6
        );

        // This should fail due to insufficient balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.InsufficientBalance.selector,
                (Quantity.unwrap(buyQty) * Price.unwrap(sellPrice)) / 10 ** 18,
                100 * 10 ** 6
            )
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(3000 * 10 ** 6),
            buyQty,
            Side.BUY,
            poorUser
        );

        vm.stopPrank();
    }

    function testValidateCallerBalanceForSellOrder() public {
        // Setup a proper order book with liquidity
        // First add some buy orders to create liquidity on the buy side
        vm.startPrank(user);
        mockUSDC.mint(user, 10000 * 10 ** 6);
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            10000 * 10 ** 6
        );
        balanceManager.deposit(usdc, 10000 * 10 ** 6, user, user);

        // Place a buy order to create liquidity (1 ETH at 2900 USDC)
        Price buyPrice = Price.wrap(2900 * 10 ** 6); // 2900 USDC per ETH
        Quantity buyQty = Quantity.wrap(1 * 10 ** 18); // 1 ETH
        gtxRouter.placeOrder(weth, usdc, buyPrice, buyQty, Side.BUY, user);
        vm.stopPrank();

        // Now test seller validation
        vm.startPrank(charlie);
        // Mint ETH to charlie
        mockWETH.mint(charlie, 2 ether); // 2 ETH

        // Approve ETH to be spent
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2 ether);

        // Prepare for a SELL order of 0.5 ETH
        Quantity sellQty = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH

        // Test 1: Successful validation when sufficient balance exists (direct deposit)
        try
            gtxRouter.placeOrderWithDeposit(
                weth,
                usdc,
                Price.wrap(2800 * 10 ** 6),
                sellQty,
                Side.SELL,
                charlie
            )
        returns (OrderId orderId) {
            console.log(
                "Sell order placed successfully with ID:",
                OrderId.unwrap(orderId)
            );

            // Verify locked balances
            uint256 balanceUSDC = balanceManager.getBalance(charlie, usdc);
            console.log("Locked USDC balance:", balanceUSDC);
            // Locked amount should be 1400 USDC
            assertEq(
                balanceUSDC,
                ((((Price.unwrap(buyPrice) * Quantity.unwrap(sellQty)) /
                    10 ** 18) * (FEE_UNIT - feeTaker)) / FEE_UNIT)
            );
        } catch Error(string memory reason) {
            console.log(
                string.concat(
                    "Sell order validation failed unexpectedly: ",
                    reason
                )
            );
            assertTrue(false, "Sell order validation failed");
        }

        vm.stopPrank();

        // Test 3: Insufficient balance validation
        address poorUser = makeAddr("poor_eth_user");
        vm.startPrank(poorUser);
        mockWETH.mint(poorUser, 1 * 10 ** 17); // Only 0.1 ETH, not enough for the order
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            1 * 10 ** 17
        );

        // This should fail due to insufficient balance
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.InsufficientBalance.selector,
                5 * 10 ** 17,
                1 * 10 ** 17
            )
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(2800 * 10 ** 6),
            sellQty,
            Side.SELL,
            poorUser
        );

        vm.stopPrank();
    }

    function testMarketOrderValidation() public {
        // Setup a proper order book with liquidity on both sides
        vm.startPrank(user);
        // Add sell orders
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            10 ether
        );
        balanceManager.deposit(weth, 10 ether, user, user);
        Price sellPrice = Price.wrap(3000 * 10 ** 6); // 3000 USDC per ETH
        Quantity sellQty = Quantity.wrap(1 * 10 ** 18); // 1 ETH
        gtxRouter.placeOrder(weth, usdc, sellPrice, sellQty, Side.SELL, user);

        // Add buy orders
        mockUSDC.mint(user, 10000 * 10 ** 6);
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            10000 * 10 ** 6
        );
        balanceManager.deposit(usdc, 10000 * 10 ** 6, user, user);
        Price buyPrice = Price.wrap(2900 * 10 ** 6); // 2900 USDC per ETH
        Quantity buyQty = Quantity.wrap(1 * 10 ** 18); // 1 ETH
        gtxRouter.placeOrder(weth, usdc, buyPrice, buyQty, Side.BUY, user);
        vm.stopPrank();

        // Test market buy order validation
        address marketBuyer = makeAddr("market_buyer");
        vm.startPrank(marketBuyer);
        mockUSDC.mint(marketBuyer, 5000 * 10 ** 6); // 5000 USDC
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            5000 * 10 ** 6
        );
        balanceManager.deposit(usdc, 5000 * 10 ** 6, marketBuyer, marketBuyer);

        // Successful market buy
        Quantity buyMarketQty = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH
        OrderId marketBuyId = gtxRouter.placeMarketOrder(
            weth,
            usdc,
            buyMarketQty,
            Side.BUY,
            marketBuyer
        );
        console.log(
            "Market buy order executed with ID:",
            OrderId.unwrap(marketBuyId)
        );
        vm.stopPrank();

        // Test market sell order validation
        address marketSeller = makeAddr("market_seller");
        vm.startPrank(marketSeller);
        mockWETH.mint(marketSeller, 2 ether); // 2 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2 ether);
        balanceManager.deposit(weth, 2 ether, marketSeller, marketSeller);

        // Successful market sell
        Quantity sellMarketQty = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH
        OrderId marketSellId = gtxRouter.placeMarketOrder(
            weth,
            usdc,
            sellMarketQty,
            Side.SELL,
            marketSeller
        );
        console.log(
            "Market sell order executed with ID:",
            OrderId.unwrap(marketSellId)
        );
        vm.stopPrank();

        // Test insufficient balance market orders
        address poorMarketTrader = makeAddr("poor_market_trader");
        vm.startPrank(poorMarketTrader);

        // Insufficient ETH for market sell
        mockWETH.mint(poorMarketTrader, 1 * 10 ** 17); // Only 0.1 ETH
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            1 * 10 ** 17
        );
        balanceManager.deposit(
            weth,
            1 * 10 ** 17,
            poorMarketTrader,
            poorMarketTrader
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.InsufficientBalance.selector,
                5 * 10 ** 17,
                1 * 10 ** 17
            )
        );
        gtxRouter.placeMarketOrder(
            weth,
            usdc,
            sellMarketQty,
            Side.SELL,
            poorMarketTrader
        );

        vm.stopPrank();
    }

    function testPlaceMarketOrderWithDeposit() public {
        // First, we need to ensure there's adequate liquidity on both sides of the order book

        // Setup sell side liquidity (for BUY market orders)
        vm.startPrank(user);
        // Add sell orders at different price levels
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            10 ether
        );
        balanceManager.deposit(weth, 10 ether, user, user);

        // Place multiple sell orders to create depth in the order book
        Price sellPrice1 = Price.wrap(3000 * 10 ** 6); // 3000 USDC per ETH
        Price sellPrice2 = Price.wrap(3050 * 10 ** 6); // 3050 USDC per ETH
        Price sellPrice3 = Price.wrap(3100 * 10 ** 6); // 3100 USDC per ETH

        Quantity sellQty1 = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH
        Quantity sellQty2 = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH
        Quantity sellQty3 = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH

        gtxRouter.placeOrder(weth, usdc, sellPrice1, sellQty1, Side.SELL, user);
        gtxRouter.placeOrder(weth, usdc, sellPrice2, sellQty2, Side.SELL, user);
        gtxRouter.placeOrder(weth, usdc, sellPrice3, sellQty3, Side.SELL, user);

        // Setup buy side liquidity (for SELL market orders)
        mockUSDC.mint(user, 10000 * 10 ** 6);
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            10000 * 10 ** 6
        );
        balanceManager.deposit(usdc, 10000 * 10 ** 6, user, user);

        // Place multiple buy orders to create depth in the order book
        Price buyPrice1 = Price.wrap(2950 * 10 ** 6); // 2950 USDC per ETH
        Price buyPrice2 = Price.wrap(2900 * 10 ** 6); // 2900 USDC per ETH
        Price buyPrice3 = Price.wrap(2850 * 10 ** 6); // 2850 USDC per ETH

        Quantity buyQty1 = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH
        Quantity buyQty2 = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH
        Quantity buyQty3 = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH

        gtxRouter.placeOrder(weth, usdc, buyPrice1, buyQty1, Side.BUY, user);
        gtxRouter.placeOrder(weth, usdc, buyPrice2, buyQty2, Side.BUY, user);
        gtxRouter.placeOrder(weth, usdc, buyPrice3, buyQty3, Side.BUY, user);

        // Log the order book state to confirm liquidity
        IOrderBook.PriceVolume memory bestSellPrice = gtxRouter.getBestPrice(
            weth,
            usdc,
            Side.SELL
        );
        IOrderBook.PriceVolume memory bestBuyPrice = gtxRouter.getBestPrice(
            weth,
            usdc,
            Side.BUY
        );

        console.log("Best SELL price:", Price.unwrap(bestSellPrice.price));
        console.log("Best SELL volume:", bestSellPrice.volume);  // volume is already unwrapped
        console.log("Best BUY price:", Price.unwrap(bestBuyPrice.price));
        console.log("Best BUY volume:", bestBuyPrice.volume);  // volume is already unwrapped

        vm.stopPrank();

        // Verify order book has liquidity on both sides
        assertTrue(
            Price.unwrap(bestSellPrice.price) > 0,
            "No sell side liquidity"
        );
        assertTrue(
            Price.unwrap(bestBuyPrice.price) > 0,
            "No buy side liquidity"
        );

        // Test 1: Market Buy with Deposit
        address buyDepositUser = address(0x8);
        vm.startPrank(buyDepositUser);

        // Mint USDC directly to the user (not deposited yet)
        uint256 buyerUsdcAmount = 5000 * 10 ** 6; // 5000 USDC
        mockUSDC.mint(buyDepositUser, buyerUsdcAmount);

        // Approve USDC for the balance manager
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            buyerUsdcAmount
        );

        // Market buy 0.5 ETH with immediate deposit
        Quantity buyMarketQty = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH

        // Calculate expected USDC cost based on the current order book
        uint256 expectedUsdcCost = (Quantity.unwrap(buyMarketQty) *
            Price.unwrap(bestSellPrice.price)) / 10 ** 18;
        console.log("Expected USDC cost for market buy:", expectedUsdcCost);

        // This should automatically deposit USDC and execute the market order
        OrderId buyDepositOrderId = gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            buyMarketQty,
            Side.BUY,
            buyDepositUser
        );

        console.log(
            "Market buy with deposit executed with ID:",
            OrderId.unwrap(buyDepositOrderId)
        );

        // Verify the balance has been deposited and used
        uint256 usdcBalance = balanceManager.getBalance(buyDepositUser, usdc);
        uint256 ethBalance = balanceManager.getBalance(buyDepositUser, weth);

        console.log("Remaining USDC balance after market buy:", usdcBalance);
        console.log("Received ETH after market buy:", ethBalance);

        // Should have spent approximately expectedUsdcCost (plus fees)
        assertLt(usdcBalance, buyerUsdcAmount);
        assertGt(ethBalance, 0, "User should have received ETH");
        assertApproxEqRel(
            ethBalance,
            Quantity.unwrap(buyMarketQty),
            0.01e18,
            "Should have received ~0.5 ETH"
        );

        vm.stopPrank();

        // Test 2: Market Sell with Deposit
        address sellDepositUser = address(0x9);
        vm.startPrank(sellDepositUser);

        // Mint ETH directly to the user (not deposited yet)
        uint256 sellerEthAmount = 2 ether; // 2 ETH
        mockWETH.mint(sellDepositUser, sellerEthAmount);

        // Approve ETH for the balance manager
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            sellerEthAmount
        );

        // Market sell 0.5 ETH with immediate deposit
        Quantity sellMarketQty = Quantity.wrap(5 * 10 ** 17); // 0.5 ETH

        // Calculate expected USDC received based on the current order book
        uint256 expectedUsdcReceived = (Quantity.unwrap(sellMarketQty) *
            Price.unwrap(bestBuyPrice.price)) / 10 ** 18;
        console.log(
            "Expected USDC received for market sell:",
            expectedUsdcReceived
        );

        // This should automatically deposit ETH and execute the market order
        OrderId sellDepositOrderId = gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            sellMarketQty,
            Side.SELL,
            sellDepositUser
        );

        console.log(
            "Market sell with deposit executed with ID:",
            OrderId.unwrap(sellDepositOrderId)
        );

        // Verify the balance has been deposited and used
        uint256 ethBalanceAfterSell = balanceManager.getBalance(
            sellDepositUser,
            weth
        );
        uint256 receivedUsdc = balanceManager.getBalance(sellDepositUser, usdc);

        console.log(
            "Remaining ETH balance after market sell:",
            ethBalanceAfterSell
        );
        console.log("Received USDC from market sell:", receivedUsdc);

        // Should have spent 0.5 ETH and received approximately expectedUsdcReceived (minus fees)
        assertEq(
            ethBalanceAfterSell,
            0,
            "Should have 1.5 ETH remaining"
        );
        assertGt(receivedUsdc, 0, "Should have received some USDC");
        assertApproxEqRel(
            receivedUsdc,
            expectedUsdcReceived,
            0.01e18,
            "Should have received ~1475 USDC"
        );

        vm.stopPrank();

        // Test 3: Failed Market Buy with Deposit due to insufficient funds
        address poorBuyUser = address(0xa);
        vm.startPrank(poorBuyUser);

        // Mint only a small amount of USDC to the user
        uint256 poorBuyerUsdcAmount = 100 * 10 ** 6; // 100 USDC, not enough for 0.5 ETH at 3000 USDC/ETH
        mockUSDC.mint(poorBuyUser, poorBuyerUsdcAmount);

        // Approve USDC for the balance manager
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            poorBuyerUsdcAmount
        );

        bestSellPrice = gtxRouter.getBestPrice(
            weth,
            usdc,
            Side.SELL
        );
        expectedUsdcCost = (Quantity.unwrap(buyMarketQty) *
            Price.unwrap(bestSellPrice.price)) / 10 ** 18;

        // Attempt to market buy 0.5 ETH with immediate deposit - should fail
        // Expected cost: ~0.5 ETH * 3000 USDC/ETH = 1500 USDC
        console.log("Expected USDC cost for market buy:", expectedUsdcCost);
        console.log("Price:", Price.unwrap(bestSellPrice.price));
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.InsufficientBalance.selector,
                expectedUsdcCost,
                poorBuyerUsdcAmount
            )
        );
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            buyMarketQty,
            Side.BUY,
            poorBuyUser
        );

        vm.stopPrank();

        // Test 4: Failed Market Sell with Deposit due to insufficient funds
        address poorSellUser = address(0xb);
        vm.startPrank(poorSellUser);

        // Mint only a small amount of ETH to the user
        uint256 poorSellerEthAmount = 1 * 10 ** 17; // 0.1 ETH, not enough for 0.5 ETH sell
        mockWETH.mint(poorSellUser, poorSellerEthAmount);

        // Approve ETH for the balance manager
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            poorSellerEthAmount
        );

        // Attempt to market sell 0.5 ETH with immediate deposit - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.InsufficientBalance.selector,
                Quantity.unwrap(sellMarketQty),
                poorSellerEthAmount
            )
        );
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            sellMarketQty,
            Side.SELL,
            poorSellUser
        );

        vm.stopPrank();
    }

    function testPlaceOrderWithDeposit() public {
        uint256 depositAmount = 10 ether;
        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            depositAmount
        );

        PoolKey memory key = PoolKey(weth, usdc);
        // Price with 6 decimals (1 ETH = 3000 USDC)
        Price price = Price.wrap(3000 * 10 ** 6);
        // Quantity with 18 decimals (1 ETH)
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        Side side = Side.SELL;
        console.log("Setting side to SELL");

        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            price,
            quantity,
            side,
            alice
        );
        console.log(
            "Order with deposit placed with ID:",
            OrderId.unwrap(orderId)
        );

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            side,
            price
        );

        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        assertEq(orderCount, 1);
        assertEq(totalVolume, Quantity.unwrap(quantity));

        // Check the balance and locked balance from the balance manager
        uint256 balance = balanceManager.getBalance(user, weth);
        uint256 lockedBalance = balanceManager.getLockedBalance(
            user,
            address(poolManager.getPool(key).orderBook),
            weth
        );

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
            weth,
            usdc,
            price,
            Quantity.wrap(uint128(1e18)),
            Side.SELL,
            alice
        );

        (uint256 balance, uint256 lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            weth
        );

        assertEq(
            balance,
            0,
            "Alice WETH balance should be 0 after placing sell order"
        );
        assertEq(lockedBalance, 1e18, "Locked balance should be 1 ETH");

        // For BUY orders, we specify the base quantity (ETH) we want to buy
        // But we need to mint and approve the equivalent amount of USDC
        // 1 ETH at 1900 USDC/ETH = 1900 USDC
        mockUSDC.mint(alice, 1900e6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 1900e6);

        // Quantity for buy is in base asset (ETH)
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            price,
            Quantity.wrap(1e18),
            Side.BUY,
            alice
        );

        vm.stopPrank();

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            usdc
        );

        assertEq(
            balance,
            0,
            "Alice USDC balance should be 0 after placing buy order"
        );
        assertEq(lockedBalance, 1900e6, "Locked balance should be 1900 USDC");

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            weth
        );

        assertEq(balance, 1e18, "Alice WETH balance should be 1 ETH");
        assertEq(lockedBalance, 0, "Locked balance should be 0 ETH");

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.SELL,
            price
        );
        assertEq(
            orderCount,
            0,
            "Order count should be 0 after placing buy order"
        );
        assertEq(
            totalVolume,
            0,
            "Total volume should be 0 ETH after placing buy order"
        );

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.BUY,
            price
        );
        assertEq(
            orderCount,
            1,
            "Order count should be 1 after placing buy order"
        );
        assertEq(
            totalVolume,
            1e18,
            "Total volume should be 1 ETH after placing buy order"
        );
    }

    function _getBalanceAndLockedBalance(
        address user,
        address operator,
        Currency currency
    ) internal view returns (uint256 balance, uint256 lockedBalance) {
        balance = balanceManager.getBalance(user, currency);
        lockedBalance = balanceManager.getLockedBalance(
            user,
            operator,
            currency
        );
    }

    function testMatchBuyMarketOrder() public {
        // Set up a sell order
        vm.startPrank(alice);
        mockWETH.mint(alice, 1e17);  // 0.1 ETH
        assertEq(mockWETH.balanceOf(alice), 1e17, "Alice should have 0.1 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e17);

        address wethUsdcPair = address(
            poolManager.getPool(PoolKey(weth, usdc)).orderBook
        );

        // Place a sell order for 0.1 ETH at price of 1900 USDC
        Price sellPrice = Price.wrap(1900e6);
        Quantity sellQty = Quantity.wrap(1e17); // 0.1 ETH
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            sellPrice,
            sellQty,
            Side.SELL,
            alice
        );
        vm.stopPrank();

        // Check the order was placed correctly
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.SELL,
            sellPrice
        );
        assertEq(orderCount, 1, "Should have 1 sell order");
        assertEq(totalVolume, 1e17, "Volume should be 0.1 ETH");

        uint256 balance = balanceManager.getBalance(alice, weth);
        uint256 lockedBalance = balanceManager.getLockedBalance(
            alice,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            weth
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            wethUsdcPair,
            weth
        );
        assertEq(
            balance,
            0,
            "Alice WETH balance should be 0 after placing sell order"
        );
        assertEq(lockedBalance, 1e17, "Locked balance should be 0.1 ETH");

        // Now place a market buy order for 0.0001 ETH
        vm.startPrank(bob);
        // For 0.0001 ETH at price 1900 USDC/ETH, need 0.19 USDC
        mockUSDC.mint(bob, 19e4);  // 0.19 USDC
        assertEq(mockUSDC.balanceOf(bob), 19e4, "Bob should have 0.19 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 19e4);

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            bob,
            wethUsdcPair,
            usdc
        );
        assertEq(balance, 0, "Bob USDC balance should be 0 before market buy");
        assertEq(
            lockedBalance,
            0,
            "Bob USDC locked balance should be 0 before market buy"
        );

        // Quantity is in base asset (ETH) - 0.0001 ETH
        Quantity buyQty1 = Quantity.wrap(1e14);
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            buyQty1,
            Side.BUY,
            bob
        );
        vm.stopPrank();

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            bob,
            wethUsdcPair,
            usdc
        );
        assertEq(balance, 0, "Bob USDC balance should be 0 after market buy");
        assertEq(
            lockedBalance,
            0,
            "Bob USDC locked balance should be 0 after market buy"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            bob,
            wethUsdcPair,
            weth
        );
        // Calculate expected ETH received:
        // Buy amount: 0.0001 ETH
        uint256 expectedEthReceived = 1e14; // 0.0001 ETH
        // Apply taker fee (0.5%)
        uint256 feeAmount = (expectedEthReceived * 5) / 1000;
        assertEq(
            balance,
            expectedEthReceived - feeAmount,
            "Bob should receive 0.0001 ETH minus 0.5% taker fee"
        );
        assertEq(
            lockedBalance,
            0,
            "Bob WETH locked balance should be 0 after market buy"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            wethUsdcPair,
            usdc
        );
        // Calculate expected USDC received:
        // 0.0001 ETH * 1900 USDC/ETH = 0.19 USDC
        uint256 expectedUsdcReceived = 19e4; // 0.19 USDC
        // Apply maker fee (0.1%)
        feeAmount = (expectedUsdcReceived * 1) / 1000;
        assertEq(
            balance,
            expectedUsdcReceived - feeAmount,
            "Alice should receive 0.19 USDC minus 0.1% maker fee"
        );
        assertEq(
            lockedBalance,
            0,
            "Alice USDC locked balance should be 0 after market buy"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            wethUsdcPair,
            weth
        );
        assertEq(balance, 0, "Alice WETH balance should be 0 after market buy");
        assertEq(
            lockedBalance,
            1e17 - 1e14,
            "Alice WETH locked balance should be reduced by traded amount"
        );
    }

    function testMatchSellMarketOrder() public {
        // Set up a buy order
        vm.startPrank(alice);
        mockUSDC.mint(alice, 1900e6);
        assertEq(
            mockUSDC.balanceOf(alice),
            1900e6,
            "Alice should have 1900 USDC"
        );

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 1900e6);

        // Place a buy order for 1 ETH at price of 1900 USDC
        Price buyPrice = Price.wrap(1900e6);

        // Quantity is in base units - 1 ETH
        Quantity buyQty = Quantity.wrap(1e18);
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            buyPrice,
            buyQty,
            Side.BUY,
            alice
        );
        vm.stopPrank();

        // Check the order was placed correctly
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.BUY,
            buyPrice
        );
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
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            sellQty,
            Side.SELL,
            bob
        );
        vm.stopPrank();

        // Check the state of the buy order after match
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.BUY,
            buyPrice
        );
        assertEq(
            totalVolume,
            1e18 - 5e17,
            "Remaining buy volume should be 0.5 ETH (half of original)"
        );
        assertEq(
            orderCount,
            1,
            "Buy order should still exist with remaining quantity"
        );

        (uint256 balance, uint256 lockedBalance) = _getBalanceAndLockedBalance(
            bob,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            usdc
        );
        uint256 balanceAmount = 950e6;
        uint256 feeAmount = (balanceAmount * 5) / 1000; // 0.5% fee on 1900 USDC
        assertEq(
            balance,
            balanceAmount - feeAmount,
            "Bob should receive 0.5 ETH worth of USDC minus 0.5% fee"
        );
        assertEq(
            lockedBalance,
            0,
            "Bob USDC locked balance should be 0 after market sell"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            bob,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            weth
        );
        assertEq(balance, 0, "Bob WETH balance should be 0 after market sell");
        assertEq(
            lockedBalance,
            0,
            "Bob WETH locked balance should be 0 ETH after market sell"
        );

        // Alice WETH and USDC balance
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            usdc
        );
        assertEq(
            balance,
            0,
            "Alice USDC balance should be 0 after market sell"
        );
        assertEq(
            lockedBalance,
            950e6,
            "Alice USDC locked balance should be 950 USDC after market sell"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            alice,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            weth
        );
        balanceAmount = 1e18 - 5e17;
        feeAmount = (balanceAmount * 1) / 1000; // 0.1% fee on 0.5 ETH
        assertEq(
            balance,
            balanceAmount - feeAmount,
            "Alice WETH balance should be 0.5 ETH after market sell"
        );
        assertEq(
            lockedBalance,
            0,
            "Alice WETH locked balance should be 0 ETH after market sell"
        );

        vm.startPrank(charlie);
        mockWETH.mint(charlie, 5e17); // 0.5 ETH
        assertEq(
            mockWETH.balanceOf(charlie),
            5e17,
            "Charlie should have 0.5 ETH"
        );

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 5e17);

        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            Quantity.wrap(5e17),
            Side.SELL,
            charlie
        );
        vm.stopPrank();

        //Charlie WETH and USDC balance
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            charlie,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            usdc
        );
        feeAmount = (950e6 * 5) / 1000; // 0.5% fee on 1900 USDC
        assertEq(
            balance,
            950e6 - feeAmount,
            "Charlie USDC balance should be 950 USDC after market sell"
        );
        assertEq(
            lockedBalance,
            0,
            "Charlie USDC locked balance should be 0 after market sell"
        );

        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            charlie,
            address(poolManager.getPool(PoolKey(weth, usdc)).orderBook),
            weth
        );
        assertEq(
            balance,
            0,
            "Charlie WETH balance should be 0 after market sell"
        );
        assertEq(
            lockedBalance,
            0,
            "Charlie WETH locked balance should be 0 ETH after market sell"
        );

        // Check buy order should be fully matched now
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.BUY,
            buyPrice
        );
        assertEq(orderCount, 0, "Buy order should be fully matched");
        assertEq(totalVolume, 0, "Buy volume should be 0 after full match");
    }

    function testLimitOrderMatching() public {
        // Mint tokens for the test
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        assertEq(
            mockWETH.balanceOf(alice),
            initialBalanceWETH,
            "Alice should have initial WETH balance"
        );

        IERC20(Currency.unwrap(weth)).approve(
            address(balanceManager),
            initialBalanceWETH
        );
        Price price = Price.wrap(2000e6);
        Quantity quantity = Quantity.wrap(1e18); // 1 ETH
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            price,
            quantity,
            Side.SELL,
            alice
        );
        vm.stopPrank();

        vm.startPrank(bob);
        mockUSDC.mint(bob, 2000e6); // Need enough for 1 ETH at 2000 USDC
        assertEq(mockUSDC.balanceOf(bob), 2000e6, "Bob should have 2000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 2000e6);
        // For buy orders, we're now using base quantity (ETH)
        Quantity buyQuantity = Quantity.wrap(1e18); // 1 ETH
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            price,
            buyQuantity,
            Side.BUY,
            bob
        );
        vm.stopPrank();

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.SELL,
            price
        );
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(orderCount, 0, "Sell order should be fully filled");
        assertEq(totalVolume, 0, "Total volume should be 0");
    }

    function testCancelSellOrder() public {
        address trader = makeAddr("trader");
        vm.startPrank(trader);
        mockWETH.mint(trader, 1 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1 ether);

        // Place a sell order
        Price price = Price.wrap(2000e18);
        Quantity quantity = Quantity.wrap(1e18);
        Side side = Side.SELL;
        PoolKey memory key = PoolKey(weth, usdc);
        (uint256 balance, uint256 lockedBalance) = _getBalanceAndLockedBalance(
            trader,
            address(poolManager.getPool(key).orderBook),
            weth
        );
        assertEq(balance, 0, "Trader WETH balance should be 0 before order");
        assertEq(
            lockedBalance,
            0,
            "Trader WETH locked balance should be 0 before order"
        );

        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            price,
            quantity,
            side,
            trader
        );
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            trader,
            address(poolManager.getPool(key).orderBook),
            weth
        );
        assertEq(
            balance,
            0,
            "Trader WETH balance should be 0 after order placement"
        );
        assertEq(
            lockedBalance,
            Quantity.unwrap(quantity),
            "Trader WETH locked balance should be equal to quantity after order"
        );

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            side,
            price
        );
        assertEq(orderCount, 1, "Order should be placed");
        assertEq(
            totalVolume,
            Quantity.unwrap(quantity),
            "Volume should match quantity"
        );

        gtxRouter.cancelOrder(weth, usdc, orderId);
        vm.stopPrank();

        balance = balanceManager.getBalance(trader, weth);
        lockedBalance = balanceManager.getLockedBalance(
            trader,
            address(poolManager.getPool(key).orderBook),
            weth
        );
        assertEq(
            balance,
            Quantity.unwrap(quantity),
            "Trader WETH balance should be equal to quantity after cancellation"
        );
        assertEq(
            lockedBalance,
            0,
            "Trader WETH locked balance should be 0 after cancellation"
        );

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            side,
            price
        );
        assertEq(orderCount, 0, "Order should be cancelled");
        assertEq(totalVolume, 0, "Volume should be 0 after cancellation");
    }

    function testCancelBuyOrder() public {
        address trader = makeAddr("trader");
        vm.startPrank(trader);
        mockUSDC.mint(trader, 2000e6); // 2000 USDC for a buy order
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 2000e6);

        // Place a buy order - buying 1 ETH at 2000 USDC per ETH
        Price price = Price.wrap(2000e6);
        Quantity quantity = Quantity.wrap(1e18); // 1 ETH (base quantity)
        Side side = Side.BUY;
        PoolKey memory key = PoolKey(weth, usdc);

        // Check initial balances
        (uint256 balance, uint256 lockedBalance) = _getBalanceAndLockedBalance(
            trader,
            address(poolManager.getPool(key).orderBook),
            usdc
        );
        assertEq(balance, 0, "Trader USDC balance should be 0 before order");
        assertEq(
            lockedBalance,
            0,
            "Trader USDC locked balance should be 0 before order"
        );

        // Place the buy order
        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            price,
            quantity,
            side,
            trader
        );

        // Verify the order was placed correctly
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            trader,
            address(poolManager.getPool(key).orderBook),
            usdc
        );
        uint256 expectedLocked = 2000e6; // 2000 USDC (1 ETH * 2000 USDC/ETH)
        assertEq(
            balance,
            0,
            "Trader USDC balance should be 0 after order placement"
        );
        assertEq(
            lockedBalance,
            expectedLocked,
            "Trader USDC locked balance should equal order value"
        );

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            side,
            price
        );
        assertEq(orderCount, 1, "Order should be placed");
        assertEq(
            totalVolume,
            Quantity.unwrap(quantity),
            "Volume should match quantity"
        );

        // Cancel the buy order
        gtxRouter.cancelOrder(weth, usdc, orderId);
        vm.stopPrank();

        // Verify balances after cancellation
        (balance, lockedBalance) = _getBalanceAndLockedBalance(
            trader,
            address(poolManager.getPool(key).orderBook),
            usdc
        );

        assertEq(
            balance,
            expectedLocked,
            "Trader USDC balance should be equal to order value after cancellation"
        );
        assertEq(
            lockedBalance,
            0,
            "Trader USDC locked balance should be 0 after cancellation"
        );

        // Verify the order was removed from the queue
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            side,
            price
        );
        assertEq(orderCount, 0, "Order should be cancelled");
        assertEq(totalVolume, 0, "Volume should be 0 after cancellation");
    }

    function testPartialMarketOrderMatching() public {
        // Setup sell order
        vm.startPrank(alice);
        mockWETH.mint(alice, 10e18);
        assertEq(mockWETH.balanceOf(alice), 10e18, "Alice should have 10 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10e18);
        Price sellPrice = Price.wrap(1000e6);
        Quantity sellQty = Quantity.wrap(10e18); // 10 ETH
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            sellPrice,
            sellQty,
            Side.SELL,
            alice
        );
        vm.stopPrank();

        // Place partial market buy order
        vm.startPrank(bob);
        // Calculate required USDC for 6 ETH at 1000 USDC/ETH = 6000 USDC
        mockUSDC.mint(bob, 6000e6);
        assertEq(mockUSDC.balanceOf(bob), 6000e6, "Bob should have 6000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 6000e6);

        // Buy 6 ETH (base quantity)
        Quantity buyQty = Quantity.wrap(6e18); // 6 ETH
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            buyQty,
            Side.BUY,
            bob
        );
        vm.stopPrank();

        // Verify partial fill
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.SELL,
            sellPrice
        );
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
            weth,
            usdc,
            Price.wrap(1000e6),
            Quantity.wrap(10e18),
            Side.SELL,
            alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(900e6),
            Quantity.wrap(5e18),
            Side.SELL,
            alice
        );
        vm.stopPrank();

        OrderBook.PriceVolume memory bestPriceVolume = gtxRouter.getBestPrice(
            weth,
            usdc,
            Side.SELL
        );
        assertEq(
            Price.unwrap(bestPriceVolume.price),
            900e6,
            "Best sell price should be 900"
        );
    }

    function testGetNextBestPrices() public {
        // Set up sell orders at different price levels
        vm.startPrank(alice);
        mockWETH.mint(alice, 18e18); // Need 18 ETH for all orders
        assertEq(mockWETH.balanceOf(alice), 18e18, "Alice should have 18 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 18e18);
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            Quantity.wrap(10e18),
            Side.SELL,
            alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(900e6),
            Quantity.wrap(5e18),
            Side.SELL,
            alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(800e6),
            Quantity.wrap(3e18),
            Side.SELL,
            alice
        );
        vm.stopPrank();

        OrderBook.PriceVolume[] memory levels = gtxRouter.getNextBestPrices(
            weth,
            usdc,
            Side.SELL,
            Price.wrap(0),
            3
        );

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
            weth,
            usdc,
            Price.wrap(1000e6),
            Quantity.wrap(10e18),
            Side.SELL,
            alice
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(900e6),
            Quantity.wrap(5e18),
            Side.SELL,
            alice
        );
        vm.stopPrank();

        OrderBook.Order[] memory aliceOrders = gtxRouter.getUserActiveOrders(
            weth,
            usdc,
            alice
        );
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
            weth,
            usdc,
            Price.wrap(1000e6),
            Quantity.wrap(10e18),
            Side.SELL,
            alice
        );
        vm.stopPrank();

        // Try to cancel the order as bob
        vm.startPrank(bob);
        vm.expectRevert();
        gtxRouter.cancelOrder(weth, usdc, orderId);
        vm.stopPrank();
    }

    function testOrderSizeValidation() public {
        vm.startPrank(alice);
        mockWETH.mint(alice, 2000e18); // Ensure enough balance for tests
        mockUSDC.mint(alice, 10_000e6); // Adding USDC for BUY tests
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2000e18);
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            10_000e6
        );

        // Get current trading rules for reference
        IOrderBook.TradingRules memory rules = defaultTradingRules;
        console.log("Min trade amount:", Quantity.unwrap(rules.minTradeAmount));
        console.log("Min order size:", Quantity.unwrap(rules.minOrderSize));
        console.log(
            "Min amount movement:",
            Quantity.unwrap(rules.minAmountMovement)
        );
        console.log(
            "Min price movement:",
            Quantity.unwrap(rules.minPriceMovement)
        );

        // Zero quantity
        Quantity zeroAmount = Quantity.wrap(0);
        vm.expectRevert(IBalanceManager.ZeroAmount.selector);
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            zeroAmount,
            Side.SELL,
            alice
        );

        vm.expectRevert(IBalanceManager.ZeroAmount.selector);
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            zeroAmount,
            Side.BUY,
            alice
        );

        // Invalid price (zero)
        vm.expectRevert();
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(0),
            Quantity.wrap(10e18),
            Side.SELL,
            alice
        );

        // Order too small (SELL - base currency)
        Quantity tooSmallAmount = Quantity.wrap(1e13); // Smaller than min trade amount (1e14)
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.OrderTooSmall.selector,
                Quantity.unwrap(tooSmallAmount),
                Quantity.unwrap(rules.minTradeAmount)
            )
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            tooSmallAmount,
            Side.SELL,
            alice
        );

        // Order too small (BUY - now in base units)
        Quantity tooSmallBuyAmount = Quantity.wrap(1e13);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.OrderTooSmall.selector,
                Quantity.unwrap(tooSmallBuyAmount),
                Quantity.unwrap(rules.minTradeAmount)
            )
        );
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            tooSmallBuyAmount,
            Side.BUY,
            alice
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
        vm.expectRevert(IOrderBookErrors.InvalidPriceIncrement.selector);
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1_000_005e3),
            Quantity.wrap(1e18),
            Side.BUY,
            alice
        );

        // Successful minimum valid order (SELL)
        Quantity minValidAmount = Quantity.wrap(1e14);
        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            minValidAmount,
            Side.SELL,
            alice
        );
        assertGt(
            OrderId.unwrap(orderId),
            0,
            "Order should be placed successfully"
        );

        // Successful minimum valid order (BUY)
        Quantity minValidBuyAmount = Quantity.wrap(1e14);
        orderId = gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(1000e6),
            minValidBuyAmount,
            Side.BUY,
            alice
        );
        assertGt(
            OrderId.unwrap(orderId),
            0,
            "Buy order should be placed successfully"
        );

        vm.stopPrank();
    }

    function testMarketOrderWithNoLiquidity() public {
        vm.startPrank(bob);
        mockUSDC.mint(bob, initialBalanceUSDC);
        assertEq(
            mockUSDC.balanceOf(bob),
            initialBalanceUSDC,
            "Bob should have initial USDC balance"
        );

        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            initialBalanceUSDC
        );

        vm.expectRevert();
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            Quantity.wrap(10e18),
            Side.BUY,
            bob
        );

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
            assertEq(
                mockWETH.balanceOf(traders[i]),
                100e18,
                "Trader should have 100 ETH"
            );
            assertEq(
                mockUSDC.balanceOf(traders[i]),
                200_000e6,
                "Trader should have 200,000 USDC"
            );

            IERC20(Currency.unwrap(weth)).approve(
                address(balanceManager),
                100e18
            );
            IERC20(Currency.unwrap(usdc)).approve(
                address(balanceManager),
                200_000e6
            );
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
                weth,
                usdc,
                Price.wrap(price),
                buyQuantity,
                Side.BUY,
                traders[i]
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
        (uint48 buyOrderCount, uint256 buyVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.BUY,
            Price.wrap(1005e6)
        );
        assertEq(buyOrderCount, 1, "Should have 1 buy order at price 1005");
        assertEq(buyVolume, 5e18, "Buy volume should be 5 ETH");

        (uint48 sellOrderCount, uint256 sellVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.SELL,
            Price.wrap(1055e6)
        );
        assertEq(sellOrderCount, 1, "Should have 1 sell order at price 1055");
        assertEq(sellVolume, 10e18, "Sell volume should be 10e18");

        // Check order book depth
        OrderBook.PriceVolume[] memory buyLevels = gtxRouter.getNextBestPrices(
            weth,
            usdc,
            Side.BUY,
            Price.wrap(0),
            5
        );
        assertEq(buyLevels.length, 5, "Should have 5 buy price levels");
        assertEq(
            Price.unwrap(buyLevels[0].price),
            1009e6,
            "Best buy price should be 1009"
        );

        OrderBook.PriceVolume[] memory sellLevels = gtxRouter.getNextBestPrices(
            weth,
            usdc,
            Side.SELL,
            Price.wrap(0),
            5
        );
        assertEq(sellLevels.length, 5, "Should have 5 sell price levels");
        assertEq(
            Price.unwrap(sellLevels[0].price),
            1050e6,
            "Best sell price should be 1050"
        );

        // Now we'll add a market order to trigger some trades and check balances
        address marketTrader = makeAddr("marketTrader");
        vm.startPrank(marketTrader);
        mockUSDC.mint(marketTrader, 50_000e6); // Mint enough USDC for market buy
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            50_000e6
        );

        // Store initial balances of some sell traders before the trade
        address orderBookAddress = address(
            poolManager.getPool(PoolKey(weth, usdc)).orderBook
        );
        uint256 initialWethLocked10 = balanceManager.getLockedBalance(
            traders[10],
            orderBookAddress,
            weth
        );
        uint256 initialUsdcBalance10 = balanceManager.getBalance(
            traders[10],
            usdc
        );

        // Execute market buy that should match with lowest sell orders
        // Quantity is in base asset (ETH)
        Quantity marketBuyQty = Quantity.wrap(5e18); // Buy 5 ETH
        gtxRouter.placeMarketOrderWithDeposit(
            weth,
            usdc,
            marketBuyQty,
            Side.BUY,
            marketTrader
        );
        vm.stopPrank();

        // Verify balances after trade for the first sell trader (index 10)
        uint256 wethLockedAfter10 = balanceManager.getLockedBalance(
            traders[10],
            orderBookAddress,
            weth
        );
        uint256 usdcBalanceAfter10 = balanceManager.getBalance(
            traders[10],
            usdc
        );

        // Trader 10 should have sold ETH (reduced locked balance) and received USDC
        assertLt(
            wethLockedAfter10,
            initialWethLocked10,
            "Trader 10 should have less locked WETH after trade"
        );
        assertGt(
            usdcBalanceAfter10,
            initialUsdcBalance10,
            "Trader 10 should have more USDC after trade"
        );

        console.log("Trader 10 initial locked WETH:", initialWethLocked10);
        console.log("Trader 10 locked WETH after trade:", wethLockedAfter10);
        console.log("Trader 10 initial USDC balance:", initialUsdcBalance10);
        console.log("Trader 10 USDC balance after trade:", usdcBalanceAfter10);

        // Check market trader's balance after trade
        uint256 marketTraderEthBalance = balanceManager.getBalance(
            marketTrader,
            weth
        );
        uint256 marketTraderEthFee = ((initialWethLocked10 -
            wethLockedAfter10) * 5) / 1000; // 0.5% taker fee
        uint256 expectedMarketTraderEthBalance = (initialWethLocked10 -
            wethLockedAfter10) - marketTraderEthFee;

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
        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            sellPrice,
            sellQty,
            Side.SELL,
            alice
        );
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
        uint256 expectedReceived = 5e18 - ((5e18 * 5) / 1000); // 5 ETH minus 0.5% taker fee
        assertEq(
            received,
            expectedReceived,
            "Swap should return correct ETH amount after fee"
        );
        assertEq(
            mockWETH.balanceOf(bob),
            expectedReceived,
            "Bob should have received WETH"
        );

        uint256 aliceUsdcAfter = balanceManager.getBalance(alice, usdc);
        uint256 expectedUsdcIncrease = 5000e6 - ((5000e6 * 1) / 1000); // 5000 USDC minus 0.1% maker fee

        // Alice's ETH should decrease by 5 ETH (locked in order) - may need to check in balanceManager
        address orderBookAddress = address(
            poolManager.getPool(PoolKey(weth, usdc)).orderBook
        );
        uint256 aliceLockedWeth = balanceManager.getLockedBalance(
            alice,
            orderBookAddress,
            weth
        );
        assertEq(
            aliceLockedWeth,
            5e18,
            "Alice should still have 5 ETH locked in remaining orders"
        );

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
        IERC20(Currency.unwrap(usdc)).approve(
            address(balanceManager),
            40_000e6
        );

        gtxRouter.placeOrderWithDeposit(
            weth,
            usdc,
            Price.wrap(2000e6),
            Quantity.wrap(1e18), // 1 ETH (base quantity)
            Side.BUY,
            alice
        );

        // Check order was placed
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(
            weth,
            usdc,
            Side.BUY,
            Price.wrap(2000e6)
        );
        assertEq(orderCount, 1, "WETH/USDC BUY order should be placed");
        assertEq(totalVolume, 1e18, "WETH/USDC BUY volume should be 1 ETH");

        mockWBTC.mint(alice, 1e8);
        IERC20(Currency.unwrap(wbtc)).approve(address(balanceManager), 1e8);

        gtxRouter.placeOrderWithDeposit(
            wbtc,
            usdc,
            Price.wrap(30_000e6),
            Quantity.wrap(1e8),
            Side.SELL,
            alice
        );

        // Check order was placed
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(
            wbtc,
            usdc,
            Side.SELL,
            Price.wrap(30_000e6)
        );
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

        console.log(
            "WBTC received from first swap (should use multi-hop):",
            received
        );
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
        assertEq(
            received,
            expectedWbtc,
            "WBTC amount should match the calculated value"
        );

        vm.stopPrank();
    }
}
