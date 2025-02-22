// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "../src/BalanceManager.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";

contract PoolManagerTest is Test {
    PoolManager private poolManager;
    BalanceManager private balanceManager;
    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user = address(0x789);
    address private operator = address(0xABC);

    Currency private weth;
    Currency private usdc;
    MockUSDC private mockUSDC;
    MockWETH private mockWETH;

    uint256 private feeMaker = 5; // 0.5%
    uint256 private feeTaker = 1; // 0.1%
    uint256 constant FEE_UNIT = 1_000;

    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 1000000_000000;
    uint256 private initialBalanceWETH = 1000 ether;

    function setUp() public {
        balanceManager = new BalanceManager(owner, feeReceiver, feeMaker, feeTaker);
        poolManager = new PoolManager(owner, address(balanceManager));

        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();

        mockUSDC.mint(user, initialBalanceUSDC);
        mockWETH.mint(user, initialBalanceWETH);
        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));

        vm.deal(user, initialBalance);

        // Transfer ownership of BalanceManager to PoolManager
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        vm.stopPrank();
    }

    function testSetRouter() public {
        address newRouter = address(0x1234);

        // Ensure only the owner can set the router
        vm.startPrank(user);
        vm.expectRevert();
        poolManager.setRouter(newRouter);
        vm.stopPrank();

        // Set the router as the owner
        vm.startPrank(owner);
        poolManager.setRouter(newRouter);
        vm.stopPrank();
    }

    function testInitializePoolRevertsIfRouterNotSet() public {
        PoolKey memory key = PoolKey(weth, usdc);
        uint256 lotSize = 1 ether;
        uint256 maxOrderAmount = 100 ether;

        vm.expectRevert(abi.encodeWithSignature("InvalidRouter()"));
        vm.startPrank(owner);
        poolManager.createPool(key, lotSize, maxOrderAmount);
        vm.stopPrank();
    }

    function testInitializePool() public {
        PoolKey memory key = PoolKey(weth, usdc);
        uint256 lotSize = 1 ether;
        uint256 maxOrderAmount = 100 ether;

        vm.startPrank(owner);
        poolManager.setRouter(operator);
        poolManager.createPool(key, lotSize, maxOrderAmount);
        vm.stopPrank();

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        assertEq(Currency.unwrap(pool.baseCurrency), Currency.unwrap(weth));
        assertEq(Currency.unwrap(pool.quoteCurrency), Currency.unwrap(usdc));
        assertEq(pool.lotSize, lotSize);
        assertEq(pool.maxOrderAmount, maxOrderAmount);
    }

    function testGetPoolId() public view {
        PoolKey memory key = PoolKey(weth, usdc);

        PoolId expectedId = key.toId();
        PoolId actualId = poolManager.getPoolId(key);

        // Unwrap PoolId to log as a uint256
        // console.log("Expected PoolId:", uint256(PoolId.unwrap(expectedId)));
        // console.log("Actual PoolId:", uint256(PoolId.unwrap(actualId)));

        // Assert equality
        assertEq(uint256(PoolId.unwrap(expectedId)), uint256(PoolId.unwrap(actualId)));
    }
}

// function testPlaceOrder() public {
//     PoolKey memory key = PoolKey(weth, usdc);
//     uint256 lotSize = 1 ether;
//     uint256 maxOrderAmount = 100 ether;

//     vm.startPrank(owner);
//     poolManager.createPool(key, lotSize, maxOrderAmount);
//     vm.stopPrank();

//     Price price = Price.wrap(3000e8);
//     Quantity quantity = Quantity.wrap(10 ether);
//     Side side = Side.BUY;

//     console.log("Price:", Price.unwrap(price));
//     console.log("Quantity:", Quantity.unwrap(quantity));
//     console.log("Side:", side == Side.BUY ? "BUY" : "SELL");

//     (Currency currency, uint256 amount) = key.calculateAmountAndCurrency(price, quantity, side);

//     console.log("Currency:", Currency.unwrap(currency));
//     console.log("Amount:", amount);

//     if (Currency.unwrap(currency) == Currency.unwrap(weth)) {
//         mockWETH.mint(user, amount);
//         console.log("Minted Asset: WETH");
//     } else if (Currency.unwrap(currency) == Currency.unwrap(usdc)) {
//         mockUSDC.mint(user, amount);
//         console.log("Minted Asset: USDC");
//     }

//     console.log("Minted Balance for User:", IERC20(Currency.unwrap(currency)).balanceOf(user));

//     vm.startPrank(user);
//     IERC20(Currency.unwrap(currency)).approve(address(balanceManager), amount);
//     balanceManager.deposit(currency, amount);
//     OrderId orderId = poolManager.placeOrder(key, price, quantity, side);
//     vm.stopPrank();
// }
