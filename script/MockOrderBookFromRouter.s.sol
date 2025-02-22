// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";

contract MockOrderBookFromRouter is DeployHelpers {
    address usdc = 0x2E6D0aA9ca3348870c7cbbC28BF6ea90A3C1fE36;
    address weth = 0xc4CebF58836707611439e23996f4FA4165Ea6A28;
    address balanceManager = 0x9B4fD469B6236c27190749bFE3227b85c25462D7;
    address poolManager = 0x35234957aC7ba5d61257d72443F8F5f0C431fD00;
    address gtxRouter = 0xed2582315b355ad0FFdF4928Ca353773c9a588e3;

    function run() external {
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey); // Starts broadcasting transactions

        // Mint USDC & WETH
        MockUSDC(usdc).mint(owner, 100_000e6);
        MockWETH(weth).mint(owner, 10 ether);

        // Approve BalanceManager
        MockUSDC(usdc).approve(balanceManager, 100_000e6);
        MockWETH(weth).approve(balanceManager, 100 ether);

        Currency currency0 = Currency.wrap(address(weth));
        Currency currency1 = Currency.wrap(address(usdc));

        // Define PoolKey (weth, usdc)
        PoolKey memory poolKey = PoolKey({baseCurrency: currency0, quoteCurrency: currency1});

        // Place an order
        Price price = Price.wrap(30_000_000_000); // Example price 8 decimals
        Quantity quantity = Quantity.wrap(1_000_000_000_000); // Example quantity (1.0 ETH) 18 decimals
        Side side = Side.BUY; // 0 = Buy, 1 = Sell
        OrderId orderId = GTXRouter(gtxRouter).placeOrderWithDeposit(poolKey, price, quantity, side);
        console.log("Order ID:", OrderId.unwrap(orderId));

        IPoolManager.Pool memory pool = PoolManager(poolManager).getPool(poolKey);
        address orderBookAddress = address(pool.orderBook);
        console.log("OrderBook address:", orderBookAddress);

        vm.stopBroadcast();
    }
}
