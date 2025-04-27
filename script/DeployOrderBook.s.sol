// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/OrderBook.sol";
import "forge-std/Script.sol";

// contract OrderBookScript is Script {
//     OrderBook public orderBook;

//     function setUp() public {}

//     function run() public {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerPrivateKey);

//         //Example
//         orderBook = new OrderBook(
//             msg.sender, msg.sender, 100e18, 1e16, PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)))
//         );

//         vm.stopBroadcast();
//     }
// }
