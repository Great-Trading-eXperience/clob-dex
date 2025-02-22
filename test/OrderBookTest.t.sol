// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {OrderId, Quantity, Side} from "../src/types/Types.sol";
import {Currency} from "../src/types/Currency.sol";
import {PoolKey} from "../src/types/Pool.sol";
import {Price} from "../src/libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockBalanceManager} from "../src/mocks/MockBalanceManager.sol";

contract OrderBookTest is Test {
    OrderBook public orderBook;
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    address baseTokenAddress;
    address quoteTokenAddress;
    address poolManager = makeAddr("pool");

    MockBalanceManager balanceManager;

    function setUp() public {
        baseTokenAddress = address(new MockWETH());
        quoteTokenAddress = address(new MockUSDC());

        PoolKey memory poolKey =
            PoolKey({baseCurrency: Currency.wrap(baseTokenAddress), quoteCurrency: Currency.wrap(quoteTokenAddress)});

        MockBalanceManager mockBalanceManager = new MockBalanceManager(alice);
        orderBook = new OrderBook(poolManager, address(mockBalanceManager), 100000, 100, poolKey);
    }

    function testBasicOrderPlacement() public {
        vm.startPrank(poolManager);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);
        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1000));

        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(orderCount, 1);
        assertEq(totalVolume, 10);
        vm.stopPrank();
    }

    function testOrderCancellation() public {
        vm.startPrank(poolManager);
        OrderId orderId = orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);

        orderBook.cancelOrder(Side.SELL, Price.wrap(1000), orderId, alice);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1000));
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);
        vm.stopPrank();
    }

    function testMarketOrder() public {
        vm.startPrank(poolManager);
        orderBook.placeOrder(Price.wrap(2000), Quantity.wrap(20), Side.SELL, alice);

        orderBook.placeOrder(Price.wrap(1050), Quantity.wrap(10), Side.SELL, bob);

        orderBook.placeMarketOrder(Quantity.wrap(15), Side.BUY, charlie);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1000));
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(totalVolume, 0);
        assertEq(orderCount, 0);

        (orderCount, totalVolume) = orderBook.getOrderQueue(Side.SELL, Price.wrap(2000));
        console.log("Order Count:", orderCount);
        console.log("Total Volume:", totalVolume);

        assertEq(totalVolume, 15);
        assertEq(orderCount, 1);
        vm.stopPrank();
    }

    function testOrderMatching() public {
        vm.startPrank(poolManager);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);

        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.BUY, bob);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1000));

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);
        vm.stopPrank();
    }

    function testGetBestPrice() public {
        vm.startPrank(poolManager);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);
        orderBook.placeOrder(Price.wrap(900), Quantity.wrap(5), Side.SELL, alice);
        vm.stopPrank();

        OrderBook.PriceVolume memory bestPriceVolume = orderBook.getBestPrice(
            Side.SELL
        );
        assertEq(Price.unwrap(bestPriceVolume.price), 900);
    }

    function testGetNextBestPrices() public {
        vm.startPrank(poolManager);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);
        orderBook.placeOrder(Price.wrap(900), Quantity.wrap(5), Side.SELL, alice);
        orderBook.placeOrder(Price.wrap(800), Quantity.wrap(3), Side.SELL, alice);
        vm.stopPrank();

        OrderBook.PriceVolume[] memory levels = orderBook.getNextBestPrices(Side.SELL, Price.wrap(0), 3);

        assertEq(Price.unwrap(levels[0].price), 800);
        assertEq(levels[0].volume, 3);
        assertEq(Price.unwrap(levels[1].price), 900);
        assertEq(levels[1].volume, 5);
        assertEq(Price.unwrap(levels[2].price), 1000);
        assertEq(levels[2].volume, 10);
    }

    function testGetUserActiveOrders() public {
        vm.startPrank(poolManager);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);
        orderBook.placeOrder(Price.wrap(900), Quantity.wrap(5), Side.SELL, alice);
        vm.stopPrank();

        OrderBook.Order[] memory aliceOrders = orderBook.getUserActiveOrders(alice);
        assertEq(aliceOrders.length, 2);
        assertEq(alice, aliceOrders[0].user);
        assertEq(alice, aliceOrders[1].user);
    }

    function testUnauthorizedCancellation() public {
        vm.startPrank(poolManager);
        OrderId orderId = orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);

        vm.expectRevert(OrderBook.UnauthorizedCancellation.selector);
        orderBook.cancelOrder(Side.SELL, Price.wrap(1000), orderId, bob);
        vm.stopPrank();
    }

    function testGasUsageOrderPlacement() public {
        vm.startPrank(poolManager);
        uint256 gasBefore = gasleft();

        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for order placement:", gasUsed);
        vm.stopPrank();
    }

    function testOrderBookWithHundredsOfTradersbuyAndSell() public {
        vm.startPrank(poolManager);
        address[] memory traders = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            traders[i] = address(uint160(i + 1000));
        }

        for (uint256 priceLevel = 0; priceLevel < 25; priceLevel++) {
            for (uint256 traderIdx = 0; traderIdx < traders.length; traderIdx++) {
                orderBook.placeOrder(
                    Price.wrap(uint64(1000 + priceLevel)), Quantity.wrap(10), Side.BUY, traders[traderIdx]
                );
            }
        }

        for (uint256 priceLevel = 25; priceLevel < 50; priceLevel++) {
            for (uint256 traderIdx = 0; traderIdx < traders.length; traderIdx++) {
                orderBook.placeOrder(
                    Price.wrap(uint64(1000 + priceLevel)), Quantity.wrap(10), Side.SELL, traders[traderIdx]
                );
            }
        }

        (uint256 buyOrderCount,) = orderBook.getOrderQueue(Side.BUY, Price.wrap(1024));
        assertEq(buyOrderCount, 100, "Should have 100 buy orders at price 1024");

        (uint256 sellOrderCount,) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1025));
        assertEq(sellOrderCount, 100, "Should have 100 sell orders at price 1025");
        vm.stopPrank();
    }

    function testMarketOrderMatching() public {
        vm.startPrank(poolManager);
        // Setup sell orders
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);
        orderBook.placeOrder(Price.wrap(1100), Quantity.wrap(5), Side.SELL, alice);

        // Place market buy order
        orderBook.placeMarketOrder(Quantity.wrap(15), Side.BUY, bob);

        // Verify orders were matched
        (uint256 orderCount1, uint256 totalVolume1) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1000));
        (uint256 orderCount2, uint256 totalVolume2) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1100));

        assertEq(orderCount1, 0, "First order queue should be empty");
        assertEq(totalVolume1, 0, "First order queue volume should be 0");
        assertEq(orderCount2, 0, "Second order queue should be empty");
        assertEq(totalVolume2, 0, "Second order queue volume should be 0");
        vm.stopPrank();
    }

    function testPartialMarketOrderMatching() public {
        vm.startPrank(poolManager);
        // Setup sell order
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL, alice);

        // Place partial market buy order
        orderBook.placeMarketOrder(Quantity.wrap(6), Side.BUY, bob);

        // Verify partial fill
        (uint256 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(Side.SELL, Price.wrap(1000));

        assertEq(orderCount, 1, "Order should still exist");
        assertEq(totalVolume, 4, "Remaining volume should be 4");
        vm.stopPrank();
    }
}
