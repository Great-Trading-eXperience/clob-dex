// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract MockOrderBookFromRouter is DeployHelpers {
    address balanceManager;
    address poolManager;
    address gtxRouter;

    address usdc;
    address[] tokens;

    constructor(
        address _balanceManager,
        address _poolManager,
        address _gtxRouter,
        address _usdc,
        address[] memory _tokens
    ) {
        if (block.chainid == 31_337) {
            balanceManager = _balanceManager;
            poolManager = _poolManager;
            gtxRouter = _gtxRouter;
        } else {
            balanceManager = vm.envAddress("BALANCEMANAGER_CONTRACT_ADDRESS");
            poolManager = vm.envAddress("POOLMANAGER_CONTRACT_ADDRESS");
            gtxRouter = vm.envAddress("GTXROUTER_CONTRACT_ADDRESS");
        }
        usdc = _usdc;
        tokens = _tokens;
    }

    function run() external {
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey); // Starts broadcasting transactions

        // Mint USDC
        MockToken(usdc).mint(owner, 10_000_000e6);
        MockToken(usdc).approve(balanceManager, 100_000e6);

        // Loop through tokens to mint, approve, and create pool keys
        for (uint256 i = 0; i < tokens.length; i++) {
            MockToken(tokens[i]).mint(owner, 1000 ether);
            MockToken(tokens[i]).approve(balanceManager, 1000 ether);

            Currency baseCurrency = Currency.wrap(tokens[i]);
            Currency quoteCurrency = Currency.wrap(address(usdc));

            // Define PoolKey (token, usdc)
            PoolKey memory poolKey =
                PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency});

            // Place an order
            Price price = Price.wrap(280_000_000_000); // Example price 8 decimals
            Quantity quantity = Quantity.wrap(1 ether); // Example quantity (1.0 ETH) 18 decimals
            Side side = Side.BUY; // 0 = Buy, 1 = Sell
            OrderId orderId =
                GTXRouter(gtxRouter).placeOrderWithDeposit(poolKey, price, quantity, side);
            console.log("Order ID:", OrderId.unwrap(orderId));

            IPoolManager.Pool memory pool = PoolManager(poolManager).getPool(poolKey);
            address orderBookAddress = address(pool.orderBook);
            console.log("OrderBook address:", orderBookAddress);
        }

        vm.stopBroadcast();
    }
}
