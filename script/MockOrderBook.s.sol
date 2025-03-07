// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/interfaces/IOrderBook.sol";
import "../src/OrderBook.sol";
import "../src/types/Types.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/mocks/MockBalanceManager.sol";

contract MockOrderBookScript is Script {
    OrderBook public orderBook;

    address[] public traders;
    uint256[] public privateKeys;

    constructor() {
        traders = [
            0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC,
            0x90F79bf6EB2c4f870365E785982E1f101E93b906,
            0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65,
            0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc,
            0x976EA74026E726554dB657fA54763abd0C3a0aa9,
            0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
            0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
            0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
        ];

        privateKeys = [
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
            0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
            0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a,
            0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
            0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a,
            0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba,
            0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e,
            0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356,
            0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97,
            0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
        ];
    }

    // function setUp() public {}

    // function run() public {
    //     vm.startBroadcast();
    //     address baseTokenAddress = address(new MockWETH());
    //     address quoteTokenAddress = address(new MockUSDC());

    //     PoolKey memory poolKey = PoolKey({
    //         baseCurrency: Currency.wrap(baseTokenAddress),
    //         quoteCurrency: Currency.wrap(quoteTokenAddress)
    //     });

    //     MockBalanceManager balanceeManager = new MockBalanceManager(msg.sender);
    //     orderBook = new OrderBook(msg.sender, address(balanceeManager), 1000e18, 1e16, poolKey);
    //     vm.stopBroadcast();

    //     createBuyOrders();
    //     createSellOrders();
    //     simulateLimitOrderMatch();
    //     simulateMarketOrderMatch();
    //     simulateOrderCancellation();
    // }

    function simulateLimitOrderMatch() private {
        uint64 matchPrice = 1900e8;
        uint128 quantity = 50e18;

        vm.startBroadcast(privateKeys[0]);
        orderBook.placeOrder(Price.wrap(matchPrice), Quantity.wrap(quantity), Side.SELL, traders[0]);
        vm.stopBroadcast();

        vm.startBroadcast(privateKeys[9]);
        orderBook.placeOrder(Price.wrap(matchPrice), Quantity.wrap(quantity), Side.BUY, traders[9]);
        vm.stopBroadcast();

        vm.startBroadcast(privateKeys[9]);
        orderBook.placeOrder(Price.wrap(matchPrice), Quantity.wrap(quantity), Side.SELL, traders[9]);
        vm.stopBroadcast();

        vm.startBroadcast(privateKeys[0]);
        orderBook.placeOrder(Price.wrap(matchPrice), Quantity.wrap(quantity), Side.BUY, traders[0]);
        vm.stopBroadcast();
    }

    function simulateMarketOrderMatch() private {
        uint128 marketQuantity = 125e18;

        vm.startBroadcast(privateKeys[2]);
        orderBook.placeMarketOrder(Quantity.wrap(marketQuantity), Side.BUY, traders[2]);
        vm.stopBroadcast();

        vm.startBroadcast(privateKeys[9]);
        orderBook.placeMarketOrder(Quantity.wrap(marketQuantity), Side.SELL, traders[9]);
        vm.stopBroadcast();

        vm.startBroadcast(privateKeys[9]);
        orderBook.placeMarketOrder(Quantity.wrap(10e18), Side.SELL, traders[9]);
        vm.stopBroadcast();

        vm.startBroadcast(privateKeys[9]);
        orderBook.placeMarketOrder(Quantity.wrap(5e18), Side.SELL, traders[9]);
        vm.stopBroadcast();
    }

    function simulateOrderCancellation() private {
        uint64 cancelPrice = 1875e8;
        uint128 cancelQuantity = 25e18;

        vm.startBroadcast(privateKeys[0]);
        OrderId orderId = orderBook.placeOrder(
            Price.wrap(cancelPrice), Quantity.wrap(cancelQuantity), Side.BUY, traders[0]
        );

        orderBook.cancelOrder(Side.BUY, Price.wrap(cancelPrice), orderId, traders[0]);
        vm.stopBroadcast();
    }

    function createBuyOrders() private {
        uint64 basePrice = 1800e8;
        uint64 priceStep = 1e8;
        uint128 fixedQuantity = 100e18;

        for (uint256 i = 0; i < 10; i++) {
            uint64 price = basePrice + (99 - uint64(i)) * priceStep;

            vm.startBroadcast(privateKeys[i % privateKeys.length]);
            orderBook.placeOrder(
                Price.wrap(price),
                Quantity.wrap(fixedQuantity),
                Side.BUY,
                traders[i % traders.length]
            );
            vm.stopBroadcast();
        }
    }

    function createSellOrders() private {
        uint64 basePrice = 1901e8;
        uint64 priceStep = 1e8;
        uint128 fixedQuantity = 100e18;

        for (uint256 i = 0; i < 10; i++) {
            uint64 price = basePrice + (uint64(i) * priceStep);

            vm.startBroadcast(privateKeys[i % privateKeys.length]);
            orderBook.placeOrder(
                Price.wrap(price),
                Quantity.wrap(fixedQuantity),
                Side.SELL,
                traders[i % traders.length]
            );
            vm.stopBroadcast();
        }
    }
}
