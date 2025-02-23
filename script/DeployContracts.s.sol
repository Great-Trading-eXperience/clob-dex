// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import "forge-std/Vm.sol";

contract DeployContracts is DeployHelpers {
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
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        uint256 feeMaker = 1; // Example fee maker value
        uint256 feeTaker = 5; // Example fee taker value
        uint256 lotSize = 1e18; // Example lot size
        uint256 maxOrderAmount = 500e18; // Example max order amount

        balanceManager = new BalanceManager(owner, owner, feeMaker, feeTaker);
        console.log("BalanceManager deployed at:", address(balanceManager));

        poolManager = new PoolManager(owner, address(balanceManager));
        console.log("PoolManager deployed at:", address(poolManager));

        router = new GTXRouter(address(poolManager), address(balanceManager));
        console.log("GTXRouter deployed at:", address(router));

        Currency quoteCurrency = Currency.wrap(address(usdc));

        // Define a PoolKey with example values

        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));

        uint256 tokensLength = tokens.length;

        for (uint256 i = 0; i < tokensLength; ++i) {
            Currency baseCurrency = Currency.wrap(tokens[i]);
            PoolKey memory poolKey =
                PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency});
            poolManager.createPool(poolKey, lotSize, maxOrderAmount);
        }

        vm.stopBroadcast();

        exportDeployments();

        return (address(balanceManager), address(poolManager), address(router));
    }
}
