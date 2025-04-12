// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import "../src/PoolManager.sol";
import "../src/BalanceManager.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/OrderBook.sol";

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
    uint256 constant FEE_UNIT = 1000;

    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 1_000_000_000_000;
    uint256 private initialBalanceWETH = 1000 ether;

    // Default trading rules
    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        balanceManager = new BalanceManager(owner, feeReceiver, feeMaker, feeTaker);
        // balanceManager = new BalanceManager();
        poolManager = new PoolManager(owner, address(balanceManager));

        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();

        mockUSDC.mint(user, initialBalanceUSDC);
        mockWETH.mint(user, initialBalanceWETH);
        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));

        vm.deal(user, initialBalance);

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: Quantity.wrap(uint128(1e14)), // 0.0001 ETH,
            minAmountMovement: Quantity.wrap(uint128(1e14)), // 0.0001 ETH
            minOrderSize: Quantity.wrap(uint128(5e6)), // 5 USDC
            minPriceMovement: Quantity.wrap(uint128(1e4)), // 0.01 USDC with 6 decimals
            slippageTreshold: 20 // 20%
        });

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

        vm.expectRevert(abi.encodeWithSignature("InvalidRouter()"));
        vm.startPrank(owner);
        poolManager.createPool(weth, usdc, defaultTradingRules);
        vm.stopPrank();
    }

    function testInitializePool() public {
        PoolKey memory key = PoolKey(weth, usdc);

        vm.startPrank(owner);
        poolManager.setRouter(operator);
        poolManager.createPool(weth, usdc, defaultTradingRules);
        vm.stopPrank();

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        assertEq(Currency.unwrap(pool.baseCurrency), Currency.unwrap(weth));
        assertEq(Currency.unwrap(pool.quoteCurrency), Currency.unwrap(usdc));
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
