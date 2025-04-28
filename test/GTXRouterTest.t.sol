// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";

import "../src/OrderBook.sol";
import "../src/PoolManager.sol";
import {IOrderBookErrors} from "../src/interfaces/IOrderBookErrors.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Test, console} from "forge-std/Test.sol";

contract GTXRouterTest is Test {
    GTXRouter private gtxRouter;
    PoolManager private poolManager;
    BalanceManager private balanceManager;

    address private owner = address(0x1);
    address private feeReceiver = address(0x2);
    address private user = address(0x3);

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
    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        (BeaconProxy routerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(GTXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        gtxRouter = GTXRouter(address(routerProxy));

        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();
        mockWBTC = new MockToken("Mock WBTC", "mWBTC", 8);

        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));
        wbtc = Currency.wrap(address(mockWBTC));

        vm.deal(user, initialBalance);

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH
            minAmountMovement: 1e14, // 0.0001 ETH
            minOrderSize: 1e4, // 0.01 USDC
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
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
                minTradeAmount: 1e3, // 0.00001 BTC (8 decimals)
                minAmountMovement: 1e3, // 0.00001 BTC (8 decimals)
                minOrderSize: 1e4, // 0.01 USDC (6 decimals)
                minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
            })
        );
        vm.stopPrank();
    }

    function _getPool(Currency currency1, Currency currency2) internal view returns (IPoolManager.Pool memory pool) {
        IPoolManager _poolManager = IPoolManager(poolManager);
        PoolKey memory key = _poolManager.createPoolKey(currency1, currency2);

        return _poolManager.getPool(key);
    }

    function testPlaceLimitOrder() public {
        vm.startPrank(alice);
        uint128 price = 2000e6;
        uint128 quantity = 1e18; // 1 ETH
        mockWETH.mint(alice, quantity);
        assertEq(mockWETH.balanceOf(alice), quantity, "Alice should have initial WETH balance");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), quantity);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        vm.startSnapshotGas("OrderBook", "PlaceLimitOrder");
        uint48 orderId = gtxRouter.placeOrderWithDeposit(pool, price, quantity, IOrderBook.Side.SELL, alice);
        vm.stopPrank();
        vm.stopSnapshotGas();

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);

        // Assertions for order count and total volume
        assertEq(orderCount, 1, "Order count should be 1 after placing the limit order");
        assertEq(totalVolume, quantity, "Total volume should match the placed order quantity");

        // Assertions for the order details
        IOrderBook.Order memory order = gtxRouter.getOrder(weth, usdc, orderId);
        assertEq(order.id, orderId, "Order ID should match the returned order ID");
        assertEq(order.price, price, "Order price should match the placed price");
        assertEq(order.quantity, quantity, "Order quantity should match the placed quantity");
        assertEq(uint8(order.side), uint8(IOrderBook.Side.SELL), "Order side should be SELL");
    }

    function testValidateCallerBalanceForBuyOrder() public {
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // First add some sell orders to create liquidity on the sell side
        vm.startPrank(user);
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10 ether);
        balanceManager.deposit(weth, 10 ether, user, user);

        uint128 sellPrice = uint128(3000 * 10 ** 6); // 3000 USDC per ETH
        uint128 sellQty = uint128(1 * 10 ** 18); // 1 ETH
        gtxRouter.placeOrder(pool, sellPrice, sellQty, IOrderBook.Side.SELL, user);
        vm.stopPrank();

        // Now test buyer validation
        vm.startPrank(bob);
        mockUSDC.mint(bob, 5000 * 10 ** 6); // 5000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 5000 * 10 ** 6);

        // Prepare for a BUY order of 0.5 ETH
        uint128 buyQty = 5 * 10 ** 17; // 0.5 ETH

        // Test 1: Successful validation when sufficient balance exists (direct deposit)
        uint48 orderId;
        try gtxRouter.placeOrderWithDeposit(pool, 3000 * 10 ** 6, buyQty, IOrderBook.Side.BUY, bob) returns (
            uint48 returnedOrderId
        ) {
            orderId = returnedOrderId;
            console.log("Buy order placed successfully with ID:", orderId);

            // Verify locked balances
            uint256 balanceWETH = balanceManager.getBalance(bob, weth);

            // Calculate expected amount: 0.5 ETH * 3100 USDC/ETH = 1550 USDC
            uint256 baseAmount = 5 * 10 ** 17; // 0.5 ETH
            uint256 expectedBalance = (baseAmount * (FEE_UNIT - feeTaker)) / FEE_UNIT;
            console.log("Expected balance:", expectedBalance);

            assertEq(balanceWETH, expectedBalance, "WETH balance should match the order amount");
        } catch Error(string memory reason) {
            console.log(string.concat("Buy order validation failed unexpectedly: ", reason));
            assertTrue(false, "Buy order validation failed");
        }
        vm.stopPrank();

        // Test 2: Insufficient balance validation
        address poorUser = makeAddr("poorUser");
        vm.startPrank(poorUser);
        mockUSDC.mint(poorUser, 100 * 10 ** 6); // Only 100 USDC, not enough for the order
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 100 * 10 ** 6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrderBookErrors.InsufficientBalance.selector, (buyQty * sellPrice) / 10 ** 18, 100 * 10 ** 6
            )
        );
        gtxRouter.placeOrderWithDeposit(pool, uint128(3000 * 10 ** 6), buyQty, IOrderBook.Side.BUY, poorUser);
        vm.stopPrank();
    }

    function testValidateCallerBalanceForSellOrder() public {
        // Setup buy liquidity: add a buy order from user to create liquidity on the BUY side
        vm.startPrank(user);
        mockUSDC.mint(user, 10_000e6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10_000e6);
        balanceManager.deposit(usdc, 10_000e6, user, user);
        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        uint128 buyPrice = 2900e6; // 2900 USDC per ETH
        uint128 buyQty = 1e18; // 1 ETH
        gtxRouter.placeOrder(pool, buyPrice, buyQty, IOrderBook.Side.BUY, user);
        vm.stopPrank();

        // Test seller validation
        vm.startPrank(charlie);
        // Mint ETH to charlie
        mockWETH.mint(charlie, 2 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2 ether);
        uint128 sellQty = 5e17; // 0.5 ETH for sell order
        uint128 sellPrice = 2900e6; // 2900e6 USDC per ETH

        try gtxRouter.placeOrderWithDeposit(pool, sellPrice, sellQty, IOrderBook.Side.SELL, charlie) returns (
            uint48 orderId
        ) {
            console.log("Sell order placed successfully with ID:", orderId);
            // For a sell order, locked balance is computed based on the matched buy price.
            uint256 expectedLocked = ((buyPrice * sellQty) / 1e18 * (FEE_UNIT - feeTaker)) / FEE_UNIT;
            uint256 sellerBalance = balanceManager.getBalance(charlie, usdc);
            console.log("Locked USDC balance:", sellerBalance);
            assertEq(sellerBalance, expectedLocked, "USDC balance should match locked amount");
        } catch {
            assertTrue(false, "Sell order validation failed unexpectedly");
        }
        vm.stopPrank();

        // Test insufficient balance validation for a seller with too little ETH
        address poorUser = makeAddr("poor_eth_user");
        vm.startPrank(poorUser);
        mockWETH.mint(poorUser, 1e17); // Only 0.1 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e17);
        vm.expectRevert(abi.encodeWithSelector(IOrderBookErrors.InsufficientBalance.selector, sellQty, 1e17));
        gtxRouter.placeOrderWithDeposit(pool, sellPrice, sellQty, IOrderBook.Side.SELL, poorUser);
        vm.stopPrank();
    }

    function testMarketOrderValidation() public {
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Setup a proper order book with liquidity on both sides
        vm.startPrank(user);
        // Add sell orders
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10 ether);
        balanceManager.deposit(weth, 10 ether, user, user);
        uint128 sellPrice = 3000 * 10 ** 6; // 3000 USDC per ETH
        uint128 sellQty = 1 * 10 ** 18; // 1 ETH
        gtxRouter.placeOrder(pool, sellPrice, sellQty, IOrderBook.Side.SELL, user);

        // Add buy orders
        mockUSDC.mint(user, 10_000 * 10 ** 6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10_000 * 10 ** 6);
        balanceManager.deposit(usdc, 10_000 * 10 ** 6, user, user);
        uint128 buyPrice = 2900 * 10 ** 6; // 2900 USDC per ETH
        uint128 buyQty = 1 * 10 ** 18; // 1 ETH
        gtxRouter.placeOrder(pool, buyPrice, buyQty, IOrderBook.Side.BUY, user);
        vm.stopPrank();

        // Test market buy order validation
        address marketBuyer = makeAddr("market_buyer");
        vm.startPrank(marketBuyer);
        mockUSDC.mint(marketBuyer, 5000 * 10 ** 6); // 5000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 5000 * 10 ** 6);
        balanceManager.deposit(usdc, 5000 * 10 ** 6, marketBuyer, marketBuyer);

        // Successful market buy
        uint128 buyMarketQty = 5 * 10 ** 17; // 0.5 ETH
        uint48 marketBuyId = gtxRouter.placeMarketOrder(pool, buyMarketQty, IOrderBook.Side.BUY, marketBuyer);
        console.log("Market buy order executed with ID:", marketBuyId);
        vm.stopPrank();

        // Test market sell order validation
        address marketSeller = makeAddr("market_seller");
        vm.startPrank(marketSeller);
        mockWETH.mint(marketSeller, 2 ether); // 2 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 2 ether);
        balanceManager.deposit(weth, 2 ether, marketSeller, marketSeller);

        // Successful market sell
        uint128 sellMarketQty = 5 * 10 ** 17; // 0.5 ETH
        uint48 marketSellId = gtxRouter.placeMarketOrder(pool, sellMarketQty, IOrderBook.Side.SELL, marketSeller);
        console.log("Market sell order executed with ID:", marketSellId);
        vm.stopPrank();

        // Test insufficient balance market orders
        address poorMarketTrader = makeAddr("poor_market_trader");
        vm.startPrank(poorMarketTrader);

        // Insufficient ETH for market sell
        mockWETH.mint(poorMarketTrader, 1 * 10 ** 17); // Only 0.1 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1 * 10 ** 17);
        balanceManager.deposit(weth, 1 * 10 ** 17, poorMarketTrader, poorMarketTrader);

        vm.expectRevert(
            abi.encodeWithSelector(IOrderBookErrors.InsufficientBalance.selector, 5 * 10 ** 17, 1 * 10 ** 17)
        );
        gtxRouter.placeMarketOrder(pool, sellMarketQty, IOrderBook.Side.SELL, poorMarketTrader);

        vm.stopPrank();
    }

    function testPlaceMarketOrderWithDeposit() public {
        // First, we need to ensure there's adequate liquidity on both sides of the order book

        // Setup sell side liquidity (for BUY market orders)
        vm.startPrank(user);
        // Add sell orders at different price levels
        mockWETH.mint(user, 10 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10 ether);
        balanceManager.deposit(weth, 10 ether, user, user);

        // Place multiple sell orders to create depth in the order book
        uint128 sellPrice1 = 3000 * 10 ** 6; // 3000 USDC per ETH
        uint128 sellPrice2 = 3050 * 10 ** 6; // 3050 USDC per ETH
        uint128 sellPrice3 = 3100 * 10 ** 6; // 3100 USDC per ETH

        uint128 sellQty1 = 5 * 10 ** 17; // 0.5 ETH
        uint128 sellQty2 = 3 * 10 ** 17; // 0.3 ETH
        uint128 sellQty3 = 2 * 10 ** 17; // 0.2 ETH

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        gtxRouter.placeOrder(pool, sellPrice1, sellQty1, IOrderBook.Side.SELL, user);
        gtxRouter.placeOrder(pool, sellPrice2, sellQty2, IOrderBook.Side.SELL, user);
        gtxRouter.placeOrder(pool, sellPrice3, sellQty3, IOrderBook.Side.SELL, user);

        vm.stopPrank();

        // Setup buy side liquidity (for SELL market orders)
        vm.startPrank(user);
        // Add buy orders at different price levels
        mockUSDC.mint(user, 10_000 * 10 ** 6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 10_000 * 10 ** 6);
        balanceManager.deposit(usdc, 10_000 * 10 ** 6, user, user);

        uint128 buyPrice1 = 2900 * 10 ** 6; // 2900 USDC per ETH
        uint128 buyPrice2 = 2850 * 10 ** 6; // 2850 USDC per ETH
        uint128 buyPrice3 = 2800 * 10 ** 6; // 2800 USDC per ETH

        uint128 buyQty1 = 4 * 10 ** 17; // 0.4 ETH
        uint128 buyQty2 = 3 * 10 ** 17; // 0.3 ETH
        uint128 buyQty3 = 2 * 10 ** 17; // 0.2 ETH

        gtxRouter.placeOrder(pool, buyPrice1, buyQty1, IOrderBook.Side.BUY, user);
        gtxRouter.placeOrder(pool, buyPrice2, buyQty2, IOrderBook.Side.BUY, user);
        gtxRouter.placeOrder(pool, buyPrice3, buyQty3, IOrderBook.Side.BUY, user);

        // Log the order book state to confirm liquidity
        IOrderBook.PriceVolume memory bestSellPrice = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        IOrderBook.PriceVolume memory bestBuyPrice = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);

        console.log("Best SELL price:", bestSellPrice.price);
        console.log("Best SELL volume:", bestSellPrice.volume);
        console.log("Best BUY price:", bestBuyPrice.price);
        console.log("Best BUY volume:", bestBuyPrice.volume);

        vm.stopPrank();

        // Verify order book has liquidity on both sides
        assertTrue(bestSellPrice.price > 0, "No sell side liquidity");
        assertTrue(bestBuyPrice.price > 0, "No buy side liquidity");

        // Test 1: Market Buy with Deposit
        address buyDepositUser = address(0x8);
        vm.startPrank(buyDepositUser);

        // Mint USDC directly to the user (not deposited yet)
        uint256 buyerUsdcAmount = 5000 * 10 ** 6; // 5000 USDC
        mockUSDC.mint(buyDepositUser, buyerUsdcAmount);

        // Approve USDC for the balance manager
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), buyerUsdcAmount);

        // Market buy 0.5 ETH with immediate deposit
        uint128 buyMarketQty = 5 * 10 ** 17; // 0.5 ETH

        // Calculate expected USDC cost based on the current order book
        uint256 expectedUsdcCost = (buyMarketQty * bestSellPrice.price) / 10 ** 18;
        console.log("Expected USDC cost for market buy:", expectedUsdcCost);

        // This should automatically deposit USDC and execute the market order
        uint48 buyDepositOrderId =
            gtxRouter.placeMarketOrderWithDeposit(pool, buyMarketQty, IOrderBook.Side.BUY, buyDepositUser);

        console.log("Market buy with deposit executed with ID:", buyDepositOrderId);

        // Verify the balance has been deposited and used
        uint256 usdcBalance = balanceManager.getBalance(buyDepositUser, usdc);
        uint256 ethBalance = balanceManager.getBalance(buyDepositUser, weth);

        console.log("Remaining USDC balance after market buy:", usdcBalance);
        console.log("Received ETH after market buy:", ethBalance);

        // Should have spent approximately expectedUsdcCost (plus fees)
        assertLt(usdcBalance, buyerUsdcAmount);
        assertGt(ethBalance, 0, "User should have received ETH");
        assertApproxEqRel(ethBalance, buyMarketQty, 0.01e18, "Should have received ~0.5 ETH");

        vm.stopPrank();

        // Test 2: Market Sell with Deposit
        address sellDepositUser = address(0x9);
        vm.startPrank(sellDepositUser);

        // Mint ETH directly to the user (not deposited yet)
        uint256 sellerEthAmount = 2 ether; // 2 ETH
        mockWETH.mint(sellDepositUser, sellerEthAmount);

        // Approve ETH for the balance manager
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), sellerEthAmount);

        // Market sell 0.5 ETH with immediate deposit
        uint128 sellMarketQty = 5 * 10 ** 17; // 0.5 ETH

        // Calculate expected USDC received based on the current order book
        uint256 expectedUsdcReceived = (sellMarketQty * bestBuyPrice.price) / 10 ** 18;
        console.log("Expected USDC received for market sell:", expectedUsdcReceived);

        // This should automatically deposit ETH and execute the market order
        uint48 sellDepositOrderId =
            gtxRouter.placeMarketOrderWithDeposit(pool, sellMarketQty, IOrderBook.Side.SELL, sellDepositUser);

        console.log("Market sell with deposit executed with ID:", sellDepositOrderId);

        // Verify the balance has been deposited and used
        uint256 ethBalanceAfterSell = balanceManager.getBalance(sellDepositUser, weth);
        uint256 receivedUsdc = balanceManager.getBalance(sellDepositUser, usdc);

        console.log("Remaining ETH balance after market sell:", ethBalanceAfterSell);
        console.log("Received USDC from market sell:", receivedUsdc);

        // Should have spent 0.5 ETH and received approximately expectedUsdcReceived (minus fees)
        assertEq(ethBalanceAfterSell, 0, "Should have 1.5 ETH remaining");
        assertGt(receivedUsdc, 0, "Should have received some USDC");
        assertApproxEqRel(receivedUsdc, expectedUsdcReceived, 0.01e18, "Should have received ~1475 USDC");

        vm.stopPrank();

        // Test 3: Failed Market Buy with Deposit due to insufficient funds
        address poorBuyUser = address(0xa);
        vm.startPrank(poorBuyUser);

        // Mint only a small amount of USDC to the user
        uint256 poorBuyerUsdcAmount = 100 * 10 ** 6; // 100 USDC, not enough for 0.5 ETH at 3000 USDC/ETH
        mockUSDC.mint(poorBuyUser, poorBuyerUsdcAmount);

        // Approve USDC for the balance manager
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), poorBuyerUsdcAmount);

        bestSellPrice = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        expectedUsdcCost = (buyMarketQty * bestSellPrice.price) / 10 ** 18;

        // Attempt to market buy 0.5 ETH with immediate deposit - should fail
        // Expected cost: ~0.5 ETH * 3000 USDC/ETH = 1500 USDC
        console.log("Expected USDC cost for market buy:", expectedUsdcCost);
        console.log("Price:", bestSellPrice.price);
        vm.expectRevert(
            abi.encodeWithSelector(IOrderBookErrors.InsufficientBalance.selector, expectedUsdcCost, poorBuyerUsdcAmount)
        );
        gtxRouter.placeMarketOrderWithDeposit(pool, buyMarketQty, IOrderBook.Side.BUY, poorBuyUser);

        vm.stopPrank();

        // Test 4: Failed Market Sell with Deposit due to insufficient funds
        address poorSellUser = address(0xb);
        vm.startPrank(poorSellUser);

        // Mint only a small amount of ETH to the user
        uint256 poorSellerEthAmount = 1 * 10 ** 17; // 0.1 ETH, not enough for 0.5 ETH sell
        mockWETH.mint(poorSellUser, poorSellerEthAmount);

        // Approve ETH for the balance manager
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), poorSellerEthAmount);

        // Attempt to market sell 0.5 ETH with immediate deposit - should fail
        vm.expectRevert(
            abi.encodeWithSelector(IOrderBookErrors.InsufficientBalance.selector, sellMarketQty, poorSellerEthAmount)
        );
        gtxRouter.placeMarketOrderWithDeposit(pool, sellMarketQty, IOrderBook.Side.SELL, poorSellUser);

        vm.stopPrank();
    }

    function testPlaceOrderWithDeposit() public {
        uint256 depositAmount = 10 ether;
        vm.startPrank(alice);
        mockWETH.mint(alice, depositAmount);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        uint128 price = 3000 * 10 ** 6; // Price with 6 decimals (3000 USDC per ETH)
        uint128 quantity = 1 * 10 ** 18; // Quantity with 18 decimals (1 ETH)
        IOrderBook.Side side = IOrderBook.Side.SELL;
        console.log("Setting side to SELL");

        console.log(Currency.unwrap(pool.quoteCurrency));

        uint48 orderId = gtxRouter.placeOrderWithDeposit(pool, price, quantity, side, alice);
        console.log("Order with deposit placed with ID:", orderId);

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        assertEq(orderCount, 1);
        assertEq(totalVolume, quantity);

        // Check the balance and locked balance from the balance manager
        uint256 balance = balanceManager.getBalance(user, weth);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testIgnoreMatchOrderSameTrader() public {
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        mockUSDC.mint(alice, initialBalanceUSDC);
        uint128 price = 1900e6;

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e18);
        gtxRouter.placeOrderWithDeposit(pool, price, 1e18, IOrderBook.Side.SELL, alice);

        (uint256 balance, uint256 lockedBalance) =
            _getBalanceAndLockedBalance(alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);

        assertEq(balance, 0, "Alice WETH balance should be 0 after placing sell order");
        assertEq(lockedBalance, 1e18, "Locked balance should be 1 ETH");

        // For BUY orders, we specify the base quantity (ETH) we want to buy
        // But we need to mint and approve the equivalent amount of USDC
        // 1 ETH at 1900 USDC/ETH = 1900 USDC
        mockUSDC.mint(alice, 1900e6);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 1900e6);

        // Quantity for buy is in base asset (ETH)
        gtxRouter.placeOrderWithDeposit(pool, price, 1e18, IOrderBook.Side.BUY, alice);

        vm.stopPrank();

        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);

        assertEq(balance, 0, "Alice USDC balance should be 0 after placing buy order");
        assertEq(lockedBalance, 1900e6, "Locked balance should be 1900 USDC");

        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(alice, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);

        assertEq(balance, 1e18, "Alice WETH balance should be 1 ETH");
        assertEq(lockedBalance, 0, "Locked balance should be 0 ETH");

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        assertEq(orderCount, 0, "Order count should be 0 after placing buy order");
        assertEq(totalVolume, 0, "Total volume should be 0 ETH after placing buy order");

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, price);
        assertEq(orderCount, 1, "Order count should be 1 after placing buy order");
        assertEq(totalVolume, 1e18, "Total volume should be 1 ETH after placing buy order");
    }

    function _getBalanceAndLockedBalance(
        address _user,
        address _operator,
        Currency currency
    ) internal view returns (uint256 balance, uint256 lockedBalance) {
        balance = balanceManager.getBalance(_user, currency);
        lockedBalance = balanceManager.getLockedBalance(_user, _operator, currency);
    }

    function testMatchBuyMarketOrder() public {
        // Set up a sell order first
        vm.startPrank(alice);
        mockWETH.mint(alice, 1e17); // 0.1 ETH
        assertEq(mockWETH.balanceOf(alice), 1e17, "Alice should have 0.1 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e17);

        // Get pool for WETH/USDC pair
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 sellPrice = 1900e6; // 1900 USDC/ETH
        uint128 sellQty = 1e17; // 0.1 ETH

        // Place sell order
        gtxRouter.placeOrderWithDeposit(pool, sellPrice, sellQty, IOrderBook.Side.SELL, alice);
        vm.stopPrank();

        // Verify sell order was placed
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, sellPrice);
        assertEq(orderCount, 1, "Should have one sell order");
        assertEq(totalVolume, sellQty, "Volume should match sell quantity");

        // Bob places market buy order
        vm.startPrank(bob);
        mockUSDC.mint(bob, 2000e6); // 2000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 2000e6);

        // Market buy 0.1 ETH
        uint128 buyQty = 1e17;
        gtxRouter.placeOrderWithDeposit(
            pool,
            sellPrice, // Use same price for market order
            buyQty,
            IOrderBook.Side.BUY,
            bob
        );

        // Verify order matching sell
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, sellPrice);
        assertEq(orderCount, 0, "Sell order should be fully matched");
        assertEq(totalVolume, 0, "Volume should be 0 after match");

        // Check balances
        uint256 bobWethBalance = balanceManager.getBalance(bob, weth);
        uint256 aliceUsdcBalance = balanceManager.getBalance(alice, usdc);

        // Calculate expected amounts after fees
        uint256 expectedWeth = buyQty - ((buyQty * feeTaker) / FEE_UNIT); // Minus taker fee
        uint256 expectedUsdc = (buyQty * sellPrice) / 1e18;
        expectedUsdc = expectedUsdc - ((expectedUsdc * feeMaker) / FEE_UNIT); // Minus maker fee

        assertEq(bobWethBalance, expectedWeth, "Bob should receive ETH minus taker fee");
        assertEq(aliceUsdcBalance, expectedUsdc, "Alice should receive USDC minus maker fee");

        vm.stopPrank();
    }

    function testMatchSellMarketOrder() public {
        // Set up a buy order
        vm.startPrank(alice);
        mockUSDC.mint(alice, 1900e6);
        assertEq(mockUSDC.balanceOf(alice), 1900e6, "Alice should have 1900 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 1900e6);

        // Get pool for WETH/USDC pair
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 buyPrice = 1900e6; // 1900 USDC/ETH
        uint128 buyQty = 1e18; // 1 ETH

        // Place buy order
        gtxRouter.placeOrderWithDeposit(pool, buyPrice, buyQty, IOrderBook.Side.BUY, alice);
        vm.stopPrank();

        // Check the order was placed correctly
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, buyPrice);
        assertEq(orderCount, 1, "Should have 1 buy order");
        assertEq(totalVolume, buyQty, "Volume should match buy quantity");

        // Bob places market sell order
        vm.startPrank(bob);
        mockWETH.mint(bob, 1e18); // 1 ETH
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1e18);

        // Market sell 1 ETH
        uint128 sellQty = 1e18;
        gtxRouter.placeOrderWithDeposit(
            pool,
            buyPrice, // Use same price for market order
            sellQty,
            IOrderBook.Side.SELL,
            bob
        );

        // Verify order matching
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, buyPrice);
        assertEq(orderCount, 0, "Buy order should be fully matched");
        assertEq(totalVolume, 0, "Volume should be 0 after match");

        // Check balances
        uint256 bobUsdcBalance = balanceManager.getBalance(bob, usdc);
        uint256 aliceWethBalance = balanceManager.getBalance(alice, weth);

        // Calculate expected amounts after fees
        uint256 expectedUsdc = (sellQty * buyPrice) / 1e18;
        expectedUsdc = expectedUsdc - ((expectedUsdc * feeTaker) / FEE_UNIT); // Minus taker fee
        uint256 expectedWeth = sellQty - ((sellQty * feeMaker) / FEE_UNIT); // Minus maker fee

        assertEq(bobUsdcBalance, expectedUsdc, "Bob should receive USDC minus taker fee");
        assertEq(aliceWethBalance, expectedWeth, "Alice should receive ETH minus maker fee");

        vm.stopPrank();
    }

    function testLimitOrderMatching() public {
        // Setup sell order from Alice
        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        assertEq(mockWETH.balanceOf(alice), initialBalanceWETH, "Alice should have initial WETH balance");

        // Create pool key and get the pool properly
        PoolKey memory key = poolManager.createPoolKey(weth, usdc);
        IPoolManager.Pool memory pool = poolManager.getPool(key);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        uint128 price = 2000e6;
        uint128 quantity = 1e18; // 1 ETH
        gtxRouter.placeOrderWithDeposit(pool, price, quantity, IOrderBook.Side.SELL, alice);
        vm.stopPrank();

        // Setup buy order from Bob
        vm.startPrank(bob);
        mockUSDC.mint(bob, 2000e6); // Bob has enough USDC for 1 ETH at 2000 USDC/ETH
        assertEq(mockUSDC.balanceOf(bob), 2000e6, "Bob should have 2000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 2000e6);
        uint128 buyQuantity = 1e18; // 1 ETH
        gtxRouter.placeOrderWithDeposit(pool, price, buyQuantity, IOrderBook.Side.BUY, bob);
        vm.stopPrank();

        // Check that the sell order has been fully matched
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        console.log("Sell Order Count:", orderCount);
        console.log("Sell Total Volume:", totalVolume);

        assertEq(orderCount, 0, "Sell order should be fully filled");
        assertEq(totalVolume, 0, "Sell total volume should be 0");

        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, price);
        console.log("Buy Order Count:", orderCount);
        console.log("Buy Total Volume:", totalVolume);

        assertEq(orderCount, 0, "Buy order should be fully filled");
        assertEq(totalVolume, 0, "Buy total volume should be 0");
    }

    function testCancelSellOrder() public {
        address trader = makeAddr("trader");
        vm.startPrank(trader);

        // Mint tokens and approve for deposit
        mockWETH.mint(trader, 1 ether);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 1 ether);

        // Load pool using the _getPool helper
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Place a SELL order with deposit
        uint128 price = 3000e6; // 3000 USDC per ETH
        uint128 quantity = 1e18; // 1 ETH
        uint48 orderId = gtxRouter.placeOrderWithDeposit(pool, price, quantity, IOrderBook.Side.SELL, trader);

        // Confirm order was placed by checking the order queue
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        assertEq(orderCount, 1, "Sell order should be placed");
        assertEq(totalVolume, quantity, "Sell order volume should match");

        // Cancel the sell order
        gtxRouter.cancelOrder(pool, orderId);

        // Verify that the order is removed from the queue
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, price);
        assertEq(orderCount, 0, "Sell order should be canceled");
        assertEq(totalVolume, 0, "Sell order volume should be zero after cancellation");

        // Check that the locked funds have been released back to the trader
        uint256 balance = balanceManager.getBalance(trader, weth);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), weth);
        assertGt(balance, 0, "Trader's available balance should increase after cancellation");
        assertEq(lockedBalance, 0, "No funds should remain locked for the canceled order");

        vm.stopPrank();
    }

    function testCancelBuyOrder() public {
        address trader = makeAddr("trader");
        vm.startPrank(trader);
        mockUSDC.mint(trader, 2000e6); // 2000 USDC for a buy order
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 2000e6);

        // Place a buy order - buying 1 ETH at 2000 USDC per ETH
        uint128 price = 2000e6;
        uint128 quantity = 1e18; // 1 ETH (base quantity)
        IOrderBook.Side side = IOrderBook.Side.BUY;
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Check initial balances
        (uint256 balance, uint256 lockedBalance) =
            _getBalanceAndLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);
        assertEq(balance, 0, "Trader USDC balance should be 0 before order");
        assertEq(lockedBalance, 0, "Trader USDC locked balance should be 0 before order");

        // Place the buy order
        uint48 orderId = gtxRouter.placeOrderWithDeposit(pool, price, quantity, side, trader);

        // Verify the order was placed correctly
        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);
        uint256 expectedLocked = 2000e6; // 2000 USDC (1 ETH * 2000 USDC/ETH)
        assertEq(balance, 0, "Trader USDC balance should be 0 after order placement");
        assertEq(lockedBalance, expectedLocked, "Trader USDC locked balance should equal order value");

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 1, "Order should be placed");
        assertEq(totalVolume, quantity, "Volume should match quantity");

        // Cancel the buy order
        gtxRouter.cancelOrder(pool, orderId);
        vm.stopPrank();

        // Verify balances after cancellation
        (balance, lockedBalance) =
            _getBalanceAndLockedBalance(trader, address(poolManager.getPool(PoolKey(weth, usdc)).orderBook), usdc);

        assertEq(balance, expectedLocked, "Trader USDC balance should be equal to order value after cancellation");
        assertEq(lockedBalance, 0, "Trader USDC locked balance should be 0 after cancellation");

        // Verify the order was removed from the queue
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(weth, usdc, side, price);
        assertEq(orderCount, 0, "Order should be cancelled");
        assertEq(totalVolume, 0, "Volume should be 0 after cancellation");
    }

    function testPartialMarketOrderMatching() public {
        // Setup sell order
        vm.startPrank(alice);
        mockWETH.mint(alice, 10e18);
        assertEq(mockWETH.balanceOf(alice), 10e18, "Alice should have 10 ETH");

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10e18);
        uint128 sellPrice = 1000e6;
        uint128 sellQty = 10e18; // 10 ETH
        gtxRouter.placeOrderWithDeposit(pool, sellPrice, sellQty, IOrderBook.Side.SELL, alice);
        vm.stopPrank();

        // Place partial market buy order
        vm.startPrank(bob);
        // Calculate required USDC for 6 ETH at 1000 USDC/ETH = 6000 USDC
        mockUSDC.mint(bob, 6000e6);
        assertEq(mockUSDC.balanceOf(bob), 6000e6, "Bob should have 6000 USDC");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 6000e6);

        // Buy 6 ETH (base quantity)
        uint128 buyQty = 6e18; // 6 ETH
        gtxRouter.placeMarketOrderWithDeposit(pool, buyQty, IOrderBook.Side.BUY, bob);
        vm.stopPrank();

        // Verify partial fill
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, sellPrice);
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

        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        uint128 price1 = 1000e6;
        uint128 quantity1 = 10e18;
        gtxRouter.placeOrderWithDeposit(pool, price1, quantity1, IOrderBook.Side.SELL, alice);

        uint128 price2 = 900e6;
        uint128 quantity2 = 5e18;
        gtxRouter.placeOrderWithDeposit(pool, price2, quantity2, IOrderBook.Side.SELL, alice);
        vm.stopPrank();

        IOrderBook.PriceVolume memory bestPriceVolume = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);
        assertEq(bestPriceVolume.price, 900e6, "Best sell price should be 900");
    }

    function testGetNextBestPrices() public {
        // Set up sell orders at different price levels
        vm.startPrank(alice);
        mockWETH.mint(alice, 18e18); // Need 18 ETH for all orders
        assertEq(mockWETH.balanceOf(alice), 18e18, "Alice should have 18 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 18e18);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        uint128 price1 = 1000e6;
        uint128 quantity1 = 10e18;
        gtxRouter.placeOrderWithDeposit(pool, price1, quantity1, IOrderBook.Side.SELL, alice);

        uint128 price2 = 900e6;
        uint128 quantity2 = 5e18;
        gtxRouter.placeOrderWithDeposit(pool, price2, quantity2, IOrderBook.Side.SELL, alice);

        uint128 price3 = 800e6;
        uint128 quantity3 = 3e18;
        gtxRouter.placeOrderWithDeposit(pool, price3, quantity3, IOrderBook.Side.SELL, alice);

        vm.stopPrank();

        IOrderBook.PriceVolume[] memory levels = gtxRouter.getNextBestPrices(pool, IOrderBook.Side.SELL, 0, 3);

        assertEq(levels[0].price, 800e6);
        assertEq(levels[0].volume, 3e18);
        assertEq(levels[1].price, 900e6);
        assertEq(levels[1].volume, 5e18);
        assertEq(levels[2].price, 1000e6);
        assertEq(levels[2].volume, 10e18);
    }

    function testUnauthorizedCancellation() public {
        // Place an order for Alice
        vm.startPrank(alice);
        mockWETH.mint(alice, 10e18);
        assertEq(mockWETH.balanceOf(alice), 10e18, "Alice should have 10 ETH");

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 10e18);

        // Use _getPool to get the pool
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        uint128 price = 1000e6; // 1000 USDC per ETH
        uint128 quantity = 10e18; // 10 ETH

        // Place a SELL order
        uint48 orderId = gtxRouter.placeOrderWithDeposit(pool, price, quantity, IOrderBook.Side.SELL, alice);
        vm.stopPrank();

        // Try to cancel the order as Bob
        vm.startPrank(bob);
        vm.expectRevert();
        gtxRouter.cancelOrder(pool, orderId);
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
        console.log("Min trade amount:", rules.minTradeAmount);
        console.log("Min order size:", rules.minOrderSize);
        console.log("Min amount movement:", rules.minAmountMovement);
        console.log("Min price movement:", rules.minPriceMovement);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        // Zero quantity
        uint128 zeroAmount = 0;
        vm.expectRevert(IBalanceManager.ZeroAmount.selector);
        gtxRouter.placeOrderWithDeposit(pool, uint128(1000e6), zeroAmount, IOrderBook.Side.SELL, alice);

        vm.expectRevert(IBalanceManager.ZeroAmount.selector);
        gtxRouter.placeOrderWithDeposit(pool, uint128(1000e6), zeroAmount, IOrderBook.Side.BUY, alice);

        // Invalid price (zero)
        vm.expectRevert();
        gtxRouter.placeOrderWithDeposit(pool, uint128(0), uint128(10e18), IOrderBook.Side.SELL, alice);

        // Order too small (SELL - base currency)
        uint128 tooSmallAmount = uint128(1e13); // Smaller than min trade amount (1e14)
        vm.expectRevert(
            abi.encodeWithSelector(IOrderBookErrors.OrderTooSmall.selector, tooSmallAmount, rules.minTradeAmount)
        );
        gtxRouter.placeOrderWithDeposit(pool, uint128(1000e6), tooSmallAmount, IOrderBook.Side.SELL, alice);

        //        // Order too small (BUY - now in base units)
        uint128 tooSmallBuyAmount = uint128(1e13);

        vm.expectRevert(
            abi.encodeWithSelector(IOrderBookErrors.OrderTooSmall.selector, tooSmallBuyAmount, rules.minTradeAmount)
        );
        gtxRouter.placeOrderWithDeposit(pool, uint128(1000e6), tooSmallBuyAmount, IOrderBook.Side.BUY, alice);

        // Invalid price movement (BUY)
        // minPriceMovement is 1e4, so price of 1000.005e6 is not a valid increment
        vm.expectRevert(IOrderBookErrors.InvalidPriceIncrement.selector);
        gtxRouter.placeOrderWithDeposit(pool, uint128(1_000_005e3), uint128(1e18), IOrderBook.Side.BUY, alice);

        // Successful minimum valid order (SELL)
        uint128 minValidAmount = uint128(1e14);
        uint48 orderId =
            gtxRouter.placeOrderWithDeposit(pool, uint128(1000e6), minValidAmount, IOrderBook.Side.SELL, alice);
        assertGt(orderId, 0, "Order should be placed successfully");

        // Successful minimum valid order (BUY)
        uint128 minValidBuyAmount = uint128(1e14);
        orderId = gtxRouter.placeOrderWithDeposit(pool, uint128(1000e6), minValidBuyAmount, IOrderBook.Side.BUY, alice);
        assertGt(orderId, 0, "Buy order should be placed successfully");

        vm.stopPrank();
    }

    function testMarketOrderWithNoLiquidity() public {
        vm.startPrank(bob);
        mockUSDC.mint(bob, initialBalanceUSDC);
        assertEq(mockUSDC.balanceOf(bob), initialBalanceUSDC, "Bob should have initial USDC balance");

        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        vm.expectRevert();
        gtxRouter.placeMarketOrderWithDeposit(pool, uint128(10e18), IOrderBook.Side.BUY, bob);

        vm.stopPrank();
    }

    function testOrderBookWithManyTraders() public {
        IPoolManager.Pool memory pool = _getPool(weth, usdc);
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
            uint128 price = uint128(1000e6 + i * 1e6); // Price in USDC per ETH

            // For buy orders, quantity is in base asset (ETH)
            uint128 buyQuantity = 5e18; // 5 ETH

            gtxRouter.placeOrderWithDeposit(pool, price, buyQuantity, IOrderBook.Side.BUY, traders[i]);
            vm.stopPrank();
        }

        // Place sell orders at different price levels
        for (uint256 i = 10; i < 20; i++) {
            vm.startPrank(traders[i]);
            gtxRouter.placeOrderWithDeposit(
                pool,
                uint128(1050e6 + (i - 10) * 1e6),
                10e18, // Sell quantity in ETH
                IOrderBook.Side.SELL,
                traders[i]
            );
            vm.stopPrank();
        }

        // Check some orders
        (uint48 buyOrderCount, uint256 buyVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, 1005e6);
        console.log("buy order count", buyOrderCount);
        console.log(buyVolume);
        assertEq(buyOrderCount, 1, "Should have 1 buy order at price 1005");
        assertEq(buyVolume, 5e18, "Buy volume should be 5 ETH");

        (uint48 sellOrderCount, uint256 sellVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.SELL, 1055e6);
        assertEq(sellOrderCount, 1, "Should have 1 sell order at price 1055");
        assertEq(sellVolume, 10e18, "Sell volume should be 10e18");

        // Check order book depth
        OrderBook.PriceVolume[] memory buyLevels = gtxRouter.getNextBestPrices(pool, IOrderBook.Side.BUY, 0, 5);
        assertEq(buyLevels.length, 5, "Should have 5 buy price levels");
        assertEq(buyLevels[0].price, 1009e6, "Best buy price should be 1009");

        OrderBook.PriceVolume[] memory sellLevels = gtxRouter.getNextBestPrices(pool, IOrderBook.Side.SELL, 0, 5);
        assertEq(sellLevels.length, 5, "Should have 5 sell price levels");
        assertEq(sellLevels[0].price, 1050e6, "Best sell price should be 1050");

        // Now we'll add a market order to trigger some trades and check balances
        address marketTrader = makeAddr("marketTrader");
        vm.startPrank(marketTrader);
        mockUSDC.mint(marketTrader, 50_000e6); // Mint enough USDC for market buy
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 50_000e6);

        // Store initial balances of some sell traders before the trade
        address orderBookAddress = address(poolManager.getPool(PoolKey(weth, usdc)).orderBook);
        uint256 initialWethLocked10 = balanceManager.getLockedBalance(traders[10], orderBookAddress, weth);
        uint256 initialUsdcBalance10 = balanceManager.getBalance(traders[10], usdc);

        // Execute market buy that should match with lowest sell orders
        // Quantity is in base asset (ETH)
        uint128 marketBuyQty = 5e18; // Buy 5 ETH
        gtxRouter.placeMarketOrderWithDeposit(pool, marketBuyQty, IOrderBook.Side.BUY, marketTrader);
        vm.stopPrank();

        // Verify balances after trade for the first sell trader (index 10)
        uint256 wethLockedAfter10 = balanceManager.getLockedBalance(traders[10], orderBookAddress, weth);
        uint256 usdcBalanceAfter10 = balanceManager.getBalance(traders[10], usdc);

        // Trader 10 should have sold ETH (reduced locked balance) and received USDC
        assertLt(wethLockedAfter10, initialWethLocked10, "Trader 10 should have less locked WETH after trade");
        assertGt(usdcBalanceAfter10, initialUsdcBalance10, "Trader 10 should have more USDC after trade");

        console.log("Trader 10 initial locked WETH:", initialWethLocked10);
        console.log("Trader 10 locked WETH after trade:", wethLockedAfter10);
        console.log("Trader 10 initial USDC balance:", initialUsdcBalance10);
        console.log("Trader 10 USDC balance after trade:", usdcBalanceAfter10);

        // Check market trader's balance after trade
        uint256 marketTraderEthBalance = balanceManager.getBalance(marketTrader, weth);
        uint256 marketTraderEthFee = ((initialWethLocked10 - wethLockedAfter10) * 5) / 1000; // 0.5% taker fee
        uint256 expectedMarketTraderEthBalance = (initialWethLocked10 - wethLockedAfter10) - marketTraderEthFee;

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
        balanceManager.getBalance(alice, weth);
        uint256 aliceUsdcBefore = balanceManager.getBalance(alice, usdc);

        uint128 sellPrice = 1000e6; // 1000 USDC per ETH
        uint128 sellQty = 10e18; // 10 ETH
        IPoolManager.Pool memory pool = _getPool(weth, usdc);

        gtxRouter.placeOrderWithDeposit(pool, sellPrice, sellQty, IOrderBook.Side.SELL, alice);
        vm.stopPrank();

        // Bob will perform the swap: USDC -> WETH
        vm.startPrank(bob);
        // Calculate USDC needed: 5 ETH * 1000 USDC/ETH = 5000 USDC
        mockUSDC.mint(bob, 5000e6); // 5000 USDC
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 5000e6);

        // Quantity in base units (ETH) - we want to buy 5 ETH
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
        assertEq(received, expectedReceived, "Swap should return correct ETH amount after fee");
        assertEq(mockWETH.balanceOf(bob), expectedReceived, "Bob should have received WETH");

        uint256 aliceUsdcAfter = balanceManager.getBalance(alice, usdc);
        uint256 expectedUsdcIncrease = 5000e6 - ((5000e6 * 1) / 1000); // 5000 USDC minus 0.1% maker fee

        // Alice's ETH should decrease by 5 ETH (locked in order) - may need to check in balanceManager
        address orderBookAddress = address(poolManager.getPool(PoolKey(weth, usdc)).orderBook);
        uint256 aliceLockedWeth = balanceManager.getLockedBalance(alice, orderBookAddress, weth);
        assertEq(aliceLockedWeth, 5e18, "Alice should still have 5 ETH locked in remaining orders");

        // Alice's USDC should increase by expected amount (5000 USDC - 0.1% maker fee)
        assertEq(aliceUsdcAfter - aliceUsdcBefore, expectedUsdcIncrease, "Alice should receive USDC minus maker fee");
    }

    function testMultiHopSwap() public {
        // Setup three pools: WETH/USDC, WBTC/USDC, and a direct WETH/WBTC pool

        // Setup WETH/USDC liquidity
        vm.startPrank(alice);
        mockWETH.mint(alice, 20e18);
        mockUSDC.mint(alice, 40_000e6);

        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), 20e18);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), 40_000e6);

        IPoolManager.Pool memory pool = _getPool(weth, usdc);
        gtxRouter.placeOrderWithDeposit(pool, 2000e6, 1e18, IOrderBook.Side.BUY, alice);

        // Check order was placed
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(weth, usdc, IOrderBook.Side.BUY, 2000e6);
        assertEq(orderCount, 1, "WETH/USDC BUY order should be placed");
        assertEq(totalVolume, 1e18, "WETH/USDC BUY volume should be 1 ETH");

        mockWBTC.mint(alice, 1e8);
        IERC20(Currency.unwrap(wbtc)).approve(address(balanceManager), 1e8);

        IPoolManager.Pool memory btcUsdcPool = _getPool(wbtc, usdc);
        gtxRouter.placeOrderWithDeposit(btcUsdcPool, 30_000e6, 1e8, IOrderBook.Side.SELL, alice);

        // Check order was placed
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(wbtc, usdc, IOrderBook.Side.SELL, 30_000e6);
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
