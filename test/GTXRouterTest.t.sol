// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";

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

    Currency private weth;
    Currency private usdc;
    MockUSDC private mockUSDC;
    MockWETH private mockWETH;

    uint256 private feeMaker = 5; // 0.5%
    uint256 private feeTaker = 1; // 0.1%
    uint256 constant FEE_UNIT = 1000;

    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 100_000_000_000;
    uint256 private initialBalanceWETH = 10 ether;

    function setUp() public {
        balanceManager = new BalanceManager(owner, feeReceiver, feeMaker, feeTaker);
        poolManager = new PoolManager(owner, address(balanceManager));
        gtxRouter = new GTXRouter(address(poolManager), address(balanceManager));

        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();

        mockUSDC.mint(user, initialBalanceUSDC);
        mockWETH.mint(user, initialBalanceWETH);
        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));

        PoolKey memory key = PoolKey(weth, usdc);
        uint256 lotSize = 1 ether;
        uint256 maxOrderAmount = 100 ether;

        vm.deal(user, initialBalance);

        // Transfer ownership of BalanceManager to PoolManager
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(gtxRouter));
        poolManager.createPool(key, lotSize, maxOrderAmount);
        vm.stopPrank();
    }

    function testPlaceOrder() public {
        // Deposit first
        uint256 depositAmount = 10 ether;
        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);

        PoolKey memory key = PoolKey(weth, usdc);
        IPoolManager.Pool memory pool = poolManager.getPool(key);
        // Price with 8 decimals
        Price price = Price.wrap(3000 * 10 ** 8);
        console.log("Price:", Price.unwrap(price));

        Quantity quantity = Quantity.wrap(1 * 10 ** 18);
        console.log("Quantity:", Quantity.unwrap(quantity));

        Side side = Side.SELL;
        console.log("Setting side to SELL");

        OrderId orderId = gtxRouter.placeOrder(key, price, quantity, side);
        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, side, price);

        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        assertEq(orderCount, 1);
        assertEq(totalVolume, Quantity.unwrap(quantity));

        // Check the balance and locked balance from the balance manager
        uint256 balance = balanceManager.getBalance(user, weth);
        uint256 lockedBalance = balanceManager.getLockedBalance(user, address(pool.orderBook), weth);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        console.log("Order placed with ID:", OrderId.unwrap(orderId));

        vm.stopPrank();
    }

    function testPlaceOrderWithDeposit() public {
        uint256 depositAmount = 10 ether;
        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);

        PoolKey memory key = PoolKey(weth, usdc);
        // Price with 8 decimals
        Price price = Price.wrap(3000 * 10 ** 8);
        // Quantity with 18 decimals
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        Side side = Side.SELL;
        console.log("Setting side to SELL");

        OrderId orderId = gtxRouter.placeOrderWithDeposit(key, price, quantity, side);
        console.log("Order with deposit placed with ID:", OrderId.unwrap(orderId));

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, side, price);

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
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(3000 * 10 ** 8);
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        gtxRouter.placeOrderWithDeposit(
            key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.SELL
        );
        vm.stopPrank();

        vm.startPrank(alice);
        mockUSDC.mint(alice, initialBalanceUSDC);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);
        gtxRouter.placeOrderWithDeposit(
            key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.BUY
        );

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, Side.SELL, price);
        vm.assertEq(orderCount, 1);
        (orderCount, totalVolume) = gtxRouter.getOrderQueue(key, Side.BUY, price);
        vm.assertEq(orderCount, 1);
    }

    function testSellMatchPlaceOrder() public {
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(3000 * 10 ** 8);
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        gtxRouter.placeOrderWithDeposit(
            key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.SELL
        );
        vm.stopPrank();

        vm.startPrank(bob);
        mockUSDC.mint(bob, initialBalanceUSDC);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);
        OrderId orderId = gtxRouter.placeOrderWithDeposit(
            key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.BUY
        );

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, Side.SELL, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        console.log("Market order placed with ID:", OrderId.unwrap(orderId));

        uint256 balance = balanceManager.getBalance(user, usdc);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(key).orderBook), usdc);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testPlaceMarketOrderWithNoOrder() public {
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(3000 * 10 ** 8);
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        vm.startPrank(user);
        OrderId orderId = gtxRouter.placeMarketOrder(key, quantity, Side.BUY);
        console.log("Market order placed with ID:", OrderId.unwrap(orderId));

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, Side.BUY, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);

        uint256 balance = balanceManager.getBalance(user, usdc);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(key).orderBook), usdc);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testPlaceMarketOrderWithOrder() public {
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(3000 * 10 ** 8);
        Price price2 = Price.wrap(3500 * 10 ** 8);
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);

        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        balanceManager.deposit(weth, initialBalanceWETH);
        gtxRouter.placeOrder(key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.SELL);
        vm.stopPrank();

        vm.startPrank(bob);
        mockWETH.mint(bob, initialBalanceWETH);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        balanceManager.deposit(weth, initialBalanceWETH);
        gtxRouter.placeOrder(key, price2, Quantity.wrap(2 * Quantity.unwrap(quantity)), Side.SELL);
        vm.stopPrank();

        vm.startPrank(user);
        mockWETH.mint(user, initialBalanceUSDC);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);
        balanceManager.deposit(usdc, initialBalanceUSDC);
        OrderId orderId = gtxRouter.placeMarketOrder(key, quantity, Side.BUY);

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, Side.SELL, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        console.log("Market order placed with ID:", OrderId.unwrap(orderId));

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);

        uint256 balance = balanceManager.getBalance(user, usdc);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(key).orderBook), usdc);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testPlaceMarketOrderWithDeposit() public {
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(3000 * 10 ** 8);
        Price price2 = Price.wrap(3500 * 10 ** 8);
        Quantity quantity = Quantity.wrap(1 * 10 ** 18);
        // Quantity quantity2 = Quantity.wrap(1 * 10 ** 16);

        vm.startPrank(alice);
        mockWETH.mint(alice, initialBalanceWETH);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        // balanceManager.deposit(weth, initialBalanceWETH);
        gtxRouter.placeOrderWithDeposit(
            key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.SELL
        );
        vm.stopPrank();

        vm.startPrank(bob);
        mockWETH.mint(bob, initialBalanceWETH);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), initialBalanceWETH);
        // balanceManager.deposit(weth, initialBalanceWETH);
        gtxRouter.placeOrderWithDeposit(
            key, price2, Quantity.wrap(2 * Quantity.unwrap(quantity)), Side.SELL
        );
        vm.stopPrank();

        vm.startPrank(user);
        mockWETH.mint(user, initialBalanceUSDC);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), initialBalanceUSDC);
        // balanceManager.deposit(usdc, initialBalanceUSDC);
        OrderId orderId = gtxRouter.placeMarketOrderWithDeposit(
            key, price, Quantity.wrap(Quantity.unwrap(quantity) / 2), Side.BUY
        );

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, Side.SELL, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);
        console.log("Market order placed with ID:", OrderId.unwrap(orderId));

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);

        uint256 balance = balanceManager.getBalance(user, usdc);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(key).orderBook), usdc);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }

    function testCancelOrderFailUnauthorizedCancellation() public {
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(1000);
        OrderId orderId = OrderId.wrap(1);
        Side side = Side.BUY;

        vm.expectRevert(abi.encodeWithSignature("UnauthorizedCancellation()")); // Expect the UnauthorizedCancellation error
        gtxRouter.cancelOrder(key, side, price, orderId);
        console.log(
            "Order cancellation expected to revert with UnauthorizedCancellation for ID:",
            OrderId.unwrap(orderId)
        );
    }

    function testCancelOrder() public {
        PoolKey memory key = PoolKey(weth, usdc);
        Price price = Price.wrap(3000 * 10 ** 8);
        Quantity quantity = Quantity.wrap(10 * 10 ** 18);
        uint256 amount = 3000 * 10 * 10 ** 6;
        Side side = Side.BUY;

        // Place an order first
        vm.startPrank(user);
        IERC20(Currency.unwrap(usdc)).approve(address(balanceManager), amount);
        balanceManager.deposit(usdc, amount);
        OrderId orderId = gtxRouter.placeOrder(key, price, quantity, side);
        gtxRouter.cancelOrder(key, side, price, orderId);
        vm.stopPrank();

        (uint48 orderCount, uint256 totalVolume) = gtxRouter.getOrderQueue(key, side, price);
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);

        // Check the balance and locked balance from the balance manager
        uint256 balance = balanceManager.getBalance(user, weth);
        uint256 lockedBalance =
            balanceManager.getLockedBalance(user, address(poolManager.getPool(key).orderBook), weth);

        console.log("User Balance:", balance);
        console.log("User Locked Balance:", lockedBalance);
        vm.stopPrank();
    }
}
