/*
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployContracts is Script {
    BalanceManager public balanceManager;
    PoolManager public poolManager;
    GTXRouter public router;

    address usdc;
    address[] tokens;

    constructor(address _usdc, address[] memory _tokens) {
        usdc = _usdc;
        tokens = _tokens;
    }

    function run() public returns (address, address, address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        uint256 feeMaker = 1; // Example fee maker value
        uint256 feeTaker = 1; // Example fee taker value
        uint256 lotSize = 1e18; // Example lot size
        uint256 maxOrderAmount = 500e18; // Example max order amount

        balanceManager = new BalanceManager(owner, owner, feeMaker, feeTaker);
        // balanceManager = new BalanceManager();
        poolManager = new PoolManager(owner, address(balanceManager));
        router = new GTXRouter(address(poolManager), address(balanceManager));

        poolManager.addCommonIntermediary(Currency.wrap(address(usdc)));

        Currency quoteCurrency = Currency.wrap(address(usdc));

        // Define a PoolKey with example values

        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));

        uint256 tokensLength = tokens.length;

        IOrderBook.TradingRules memory defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: Quantity.wrap(uint128(1e14)), // 0.0001 ETH,
            minAmountMovement: Quantity.wrap(uint128(1e14)), // 0.0001 ETH
            minOrderSize: Quantity.wrap(uint128(1e4)), // 0.01 USDC
            minPriceMovement: Quantity.wrap(uint128(1e4)), // 0.01 USDC with 6 decimals
            slippageTreshold: 20 // 20%
        });

        for (uint256 i = 0; i < tokensLength; ++i) {
            Currency baseCurrency = Currency.wrap(tokens[i]);
            poolManager.createPool(baseCurrency, quoteCurrency, defaultTradingRules);
        }

        vm.stopBroadcast();

        // exportDeployments();

        return (address(balanceManager), address(poolManager), address(router));
    }
}
*/
