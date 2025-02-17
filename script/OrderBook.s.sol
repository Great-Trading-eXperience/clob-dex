// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/OrderBook.sol";

contract OrderBookScript is Script {
    OrderBook public orderBook;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // orderBook = new OrderBook();

        vm.stopBroadcast();
    }
}
