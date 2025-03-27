// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {console} from "forge-std/Test.sol";

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DeployManagers} from "./DeployManagers.s.sol";

contract PlaceOrdersFull is Script {
    address balanceManager;
    address poolManager;
    address gtxRouter;

    address usdc;
    address[] orderbooks;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 deployerPrivateKey2 = vm.envUint("PRIVATE_KEY_2");
        address owner = vm.addr(deployerPrivateKey);
        address owner2 = vm.addr(deployerPrivateKey2);

        DeployManagers deployManagers = new DeployManagers();
        (balanceManager, poolManager, gtxRouter) = deployManagers.run();
        usdc = vm.envAddress("USDC_ADDRESS");

        address weth = vm.envAddress("WETH_ADDRESS");
        address aWETH = vm.envAddress("aWETH_ADDRESS");
        address ausdc = vm.envAddress("aUSDC_ADDRESS");

        uint256 lotSize = 1e18;
        uint256 maxOrderAmount = 500e18;

        Currency baseCurrency = Currency.wrap(weth);
        Currency quoteCurrency = Currency.wrap(usdc);
        PoolKey memory initialPoolKey = PoolKey({
            baseCurrency: baseCurrency,
            quoteCurrency: quoteCurrency
        });

        vm.startBroadcast(deployerPrivateKey);

        address orderbook = PoolManager(poolManager).createPool(
            initialPoolKey,
            aWETH,
            ausdc,
            lotSize,
            maxOrderAmount
        );

        orderbooks = [
            orderbook
        ];

        MockToken(usdc).mint(owner, 1_000_000 ether);
        MockToken(usdc).mint(owner2, 1_000_000 ether);

        for (uint256 i = 0; i < orderbooks.length; ++i) {
            IOrderBook orderBook = IOrderBook(orderbooks[i]);
            PoolKey memory poolKey = orderBook.getPoolKey();

            console.log("Orderbook address:", address(orderBook));

            require(
                address(orderBook).code.length > 0,
                "Orderbook not deployed"
            );

            MockToken(Currency.unwrap(poolKey.baseCurrency)).approve(
                balanceManager,
                1000 ether
            );
            MockToken(Currency.unwrap(poolKey.quoteCurrency)).approve(
                balanceManager,
                1000 ether
            );

            string memory baseSymbol = MockToken(
                Currency.unwrap(poolKey.baseCurrency)
            ).symbol();

            Price price;

            if (keccak256(bytes(baseSymbol)) == keccak256(bytes("WETH"))) {
                price = Price.wrap(3000 * 1e6); // $3,500
            } else if (
                keccak256(bytes(baseSymbol)) == keccak256(bytes("WBTC"))
            ) {
                price = Price.wrap(50000 * 1e6); // $50,000
            } else if (
                keccak256(bytes(baseSymbol)) == keccak256(bytes("LINK"))
            ) {
                price = Price.wrap(15 * 1e6); // $15
            } else if (
                keccak256(bytes(baseSymbol)) == keccak256(bytes("UNI"))
            ) {
                price = Price.wrap(7 * 1e6); // $7
            } else {
                revert("Unsupported token");
            }

            Quantity quantity = Quantity.wrap(1 ether);
            Quantity quantity2 = Quantity.wrap(1 ether / 2);
            Side side = Side.SELL;

            OrderId sellOrderId = GTXRouter(gtxRouter).placeOrderWithDeposit(
                poolKey,
                price,
                quantity,
                Side.SELL
            );
            console.log("ORDER ID:", OrderId.unwrap(sellOrderId));
            console.log("");

            vm.stopBroadcast();

            vm.startBroadcast(deployerPrivateKey2);

            MockToken(Currency.unwrap(poolKey.baseCurrency)).approve(
                balanceManager,
                1000 ether
            );
            MockToken(Currency.unwrap(poolKey.quoteCurrency)).approve(
                balanceManager,
                1000 ether
            );
            OrderId buyOrderId = GTXRouter(gtxRouter).placeOrderWithDeposit(
                poolKey,
                price,
                quantity2,
                Side.BUY
            );
            console.log("ORDER ID:", OrderId.unwrap(buyOrderId));
            console.log("");

            vm.stopBroadcast();

            vm.startBroadcast(deployerPrivateKey);

            sellOrderId = GTXRouter(gtxRouter).placeOrderWithDeposit(
                poolKey,
                price,
                quantity,
                Side.SELL
            );
            console.log("ORDER ID:", OrderId.unwrap(sellOrderId));
            console.log("");

            vm.stopBroadcast();

            vm.startBroadcast(deployerPrivateKey2);

            MockToken(Currency.unwrap(poolKey.baseCurrency)).approve(
                balanceManager,
                1000 ether
            );
            MockToken(Currency.unwrap(poolKey.quoteCurrency)).approve(
                balanceManager,
                1000 ether
            );
            buyOrderId = GTXRouter(gtxRouter).placeOrderWithDeposit(
                poolKey,
                price,
                quantity2,
                Side.BUY
            );
            console.log("ORDER ID:", OrderId.unwrap(buyOrderId));
            console.log("");

            vm.stopBroadcast();

            vm.startBroadcast(deployerPrivateKey);

            IPoolManager.Pool memory pool = PoolManager(poolManager).getPool(
                poolKey
            );
            address orderBookAddress = address(pool.orderBook);
            console.log("OrderBook address:", orderBookAddress);
        }

        vm.stopBroadcast();
    }
}
