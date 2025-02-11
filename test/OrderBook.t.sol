// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {OrderId, Quantity, Side} from "../src/types/Types.sol";
import {Price} from "../src/libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

contract OrderBookTest is Test {
    OrderBook public orderBook;
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    function setUp() public {
        orderBook = new OrderBook();
    }

    function testBasicOrderPlacement() public {
        vm.startPrank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1000)
        );

        assertEq(orderCount, 1);
        assertEq(totalVolume, 10);
        vm.stopPrank();
    }

    function testOrderCancellation() public {
        vm.startPrank(alice);
        OrderId orderId = orderBook.placeOrder(
            Price.wrap(1000),
            Quantity.wrap(10),
            Side.SELL
        );

        orderBook.cancelOrder(Side.SELL, Price.wrap(1000), orderId);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1000)
        );

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);
        vm.stopPrank();
    }

    function testMarketOrder() public {
        vm.prank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);

        vm.prank(bob);
        orderBook.placeOrder(Price.wrap(1050), Quantity.wrap(10), Side.SELL);

        vm.prank(charlie);
        orderBook.placeMarketOrder(Quantity.wrap(15), Side.BUY);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1000)
        );

        assertEq(totalVolume, 0);
        assertEq(orderCount, 0);

        (orderCount, totalVolume) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1050)
        );

        assertEq(totalVolume, 5);
        assertEq(orderCount, 1);
    }

    function testOrderMatching() public {
        vm.prank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);

        vm.prank(bob);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.BUY);

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1000)
        );

        assertEq(orderCount, 0);
        assertEq(totalVolume, 0);
    }

    function testGetBestPrice() public {
        vm.startPrank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);
        orderBook.placeOrder(Price.wrap(900), Quantity.wrap(5), Side.SELL);
        vm.stopPrank();

        OrderBook.PriceVolume memory bestPriceVolume = orderBook.getBestPrice(
            Side.SELL
        );
        assertEq(Price.unwrap(bestPriceVolume.price), 900);
    }

    function testGetNextBestPrices() public {
        vm.startPrank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);
        orderBook.placeOrder(Price.wrap(900), Quantity.wrap(5), Side.SELL);
        orderBook.placeOrder(Price.wrap(800), Quantity.wrap(3), Side.SELL);
        vm.stopPrank();

        OrderBook.PriceVolume[] memory levels = orderBook.getNextBestPrices(
            Side.SELL,
            Price.wrap(0),
            3
        );

        assertEq(Price.unwrap(levels[0].price), 800);
        assertEq(levels[0].volume, 3);
        assertEq(Price.unwrap(levels[1].price), 900);
        assertEq(levels[1].volume, 5);
        assertEq(Price.unwrap(levels[2].price), 1000);
        assertEq(levels[2].volume, 10);
    }

    function testGetUserActiveOrders() public {
        vm.startPrank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);
        orderBook.placeOrder(Price.wrap(900), Quantity.wrap(5), Side.SELL);
        vm.stopPrank();

        OrderBook.Order[] memory aliceOrders = orderBook.getUserActiveOrders(
            alice
        );
        assertEq(aliceOrders.length, 2);
        assertEq(alice, aliceOrders[0].user);
        assertEq(alice, aliceOrders[1].user);
    }

    function testUnauthorizedCancellation() public {
        vm.prank(alice);
        OrderId orderId = orderBook.placeOrder(
            Price.wrap(1000),
            Quantity.wrap(10),
            Side.SELL
        );

        vm.prank(bob);
        vm.expectRevert(OrderBook.UnauthorizedCancellation.selector);
        orderBook.cancelOrder(Side.SELL, Price.wrap(1000), orderId);
    }

    function testGasUsageOrderPlacement() public {
        vm.startPrank(alice);
        uint256 gasBefore = gasleft();

        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);

        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for order placement:", gasUsed);
        vm.stopPrank();
    }

    function testOrderBookWithHundredsOfTradersbuyAndSell() public {
        address[] memory traders = new address[](100);
        for (uint256 i = 0; i < 100; i++) {
            traders[i] = address(uint160(i + 1000));
        }

        for (uint256 priceLevel = 0; priceLevel < 25; priceLevel++) {
            for (
                uint256 traderIdx = 0;
                traderIdx < traders.length;
                traderIdx++
            ) {
                vm.prank(traders[traderIdx]);
                orderBook.placeOrder(
                    Price.wrap(uint64(1000 + priceLevel)),
                    Quantity.wrap(10),
                    Side.BUY
                );
            }
        }

        for (uint256 priceLevel = 25; priceLevel < 50; priceLevel++) {
            for (
                uint256 traderIdx = 0;
                traderIdx < traders.length;
                traderIdx++
            ) {
                vm.prank(traders[traderIdx]);
                orderBook.placeOrder(
                    Price.wrap(uint64(1000 + priceLevel)),
                    Quantity.wrap(10),
                    Side.SELL
                );
            }
        }

        (uint256 buyOrderCount, ) = orderBook.getOrderQueue(
            Side.BUY,
            Price.wrap(1024)
        );
        assertEq(
            buyOrderCount,
            100,
            "Should have 100 buy orders at price 1024"
        );

        (uint256 sellOrderCount, ) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1025)
        );
        assertEq(
            sellOrderCount,
            100,
            "Should have 100 sell orders at price 1025"
        );
    }

    function testMarketOrderMatching() public {
        // Setup sell orders
        vm.startPrank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);
        orderBook.placeOrder(Price.wrap(1100), Quantity.wrap(5), Side.SELL);
        vm.stopPrank();

        // Place market buy order
        vm.startPrank(bob);
        orderBook.placeMarketOrder(Quantity.wrap(15), Side.BUY);
        vm.stopPrank();

        // Verify orders were matched
        (uint256 orderCount1, uint256 totalVolume1) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1000)
        );
        (uint256 orderCount2, uint256 totalVolume2) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1100)
        );

        assertEq(orderCount1, 0, "First order queue should be empty");
        assertEq(totalVolume1, 0, "First order queue volume should be 0");
        assertEq(orderCount2, 0, "Second order queue should be empty");
        assertEq(totalVolume2, 0, "Second order queue volume should be 0");
    }

    function testPartialMarketOrderMatching() public {
        // Setup sell order
        vm.startPrank(alice);
        orderBook.placeOrder(Price.wrap(1000), Quantity.wrap(10), Side.SELL);
        vm.stopPrank();

        // Place partial market buy order
        vm.startPrank(bob);
        orderBook.placeMarketOrder(Quantity.wrap(6), Side.BUY);
        vm.stopPrank();

        // Verify partial fill
        (uint256 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            Side.SELL,
            Price.wrap(1000)
        );

        assertEq(orderCount, 1, "Order should still exist");
        assertEq(totalVolume, 4, "Remaining volume should be 4");
    }
}
