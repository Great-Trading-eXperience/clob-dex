// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Script, console} from "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract MockOrderBookFromRouter is Script {
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
        // if (_balanceManager == address(0)) {
        //     balanceManager = vm.envAddress("BALANCEMANAGER_CONTRACT_ADDRESS");
        // } else {
            balanceManager = _balanceManager;
        // }

        // if (_poolManager == address(0)) {
        //     poolManager = vm.envAddress("POOLMANAGER_CONTRACT_ADDRESS");
        // } else {
            poolManager = _poolManager;
        // }

        // if (_gtxRouter == address(0)) {
        //     gtxRouter = vm.envAddress("GTXROUTER_CONTRACT_ADDRESS");
        // } else {
            gtxRouter = _gtxRouter;
        // }

        usdc = _usdc;
        tokens = _tokens;
    }

    function run() external { 
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey); // Starts broadcasting transactions

        // Loop through tokens to mint, approve, and create pool keys
        for (uint256 i = 0; i < tokens.length; i++) {
            // MockToken(tokens[i]).mint(owner, 1000 ether);
            MockToken(tokens[i]).approve(balanceManager, type(uint256).max);

            Currency baseCurrency;
            Currency quoteCurrency;

            // Used to test reverse swap. e.g. WETH -> WBTC where the exist pairs are WETH/USDC and WBTC/USDC
            // if (i == 0) {
            //     baseCurrency = Currency.wrap(tokens[i]);
            //     quoteCurrency = Currency.wrap(address(usdc));
            // } else {
            //     baseCurrency = Currency.wrap(address(usdc));
            //     quoteCurrency = Currency.wrap(tokens[i]);
            // }

            baseCurrency = Currency.wrap(tokens[i]);
            quoteCurrency = Currency.wrap(address(usdc));

            // Define PoolKey (token, usdc)
            PoolKey memory poolKey =
                PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency});

            // Place an order
            Price price = Price.wrap(280_000_000_000); // Example price 8 decimals
            Quantity quantity = Quantity.wrap(1 ether); // Example quantity (1.0 ETH) 18 decimals
            Side side = Side.SELL; // 0 = Buy, 1 = Sell

            IPoolManager.Pool memory pool = PoolManager(poolManager).getPool(poolKey);
            address orderBookAddress = address(pool.orderBook);
            
            console.log("POOL_%s_%s_ADDRESS=", MockToken(Currency.unwrap(baseCurrency)).symbol(), MockToken(Currency.unwrap(quoteCurrency)).symbol(), orderBookAddress);
        }

        vm.stopBroadcast();
    }
}
