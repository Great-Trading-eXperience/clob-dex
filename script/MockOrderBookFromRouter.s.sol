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
    address balanceManager = 0x9B4fD469B6236c27190749bFE3227b85c25462D7;
    address poolManager = 0x35234957aC7ba5d61257d72443F8F5f0C431fD00;
    address gtxRouter = 0xed2582315b355ad0FFdF4928Ca353773c9a588e3;

    address usdc;
    address weth;
    address wbtc;
    address link;
    address pepe;

    function run() external {
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey); // Starts broadcasting transactions

        address[] memory tokens = new address[](4);
        HelperConfig config = new HelperConfig();
        (usdc, weth, wbtc, link, pepe) = config.activeNetworkConfig();

        console.log("USDC address from config:", usdc);

        tokens[0] = weth;
        tokens[1] = wbtc;
        tokens[2] = link;
        tokens[3] = pepe;

        // Mint USDC
        MockToken(usdc).mint(owner, 10_000_000e6);
        MockToken(usdc).approve(balanceManager, 100_000e6);

        // Loop through tokens to mint, approve, and create pool keys
        for (uint256 i = 0; i < tokens.length; i++) {
            MockToken(tokens[i]).mint(owner, 1000 ether);
            MockToken(tokens[i]).approve(balanceManager, 100 ether);

            Currency baseCurrency = Currency.wrap(tokens[i]);
            Currency quoteCurrency = Currency.wrap(address(usdc));

            // Define PoolKey (token, usdc)
            PoolKey memory poolKey =
                PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency});

            // Place an order
            Price price = Price.wrap(30_000_000_000); // Example price 8 decimals
            Quantity quantity = Quantity.wrap(1_000_000_000_000); // Example quantity (1.0 ETH) 18 decimals
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
