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

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        vm.allowCheatcodes(owner);
        vm.startBroadcast(deployerPrivateKey);

        HelperConfig config = new HelperConfig();
        (address usdc, address weth) = config.activeNetworkConfig();
        console.log("USDC address from config:", usdc);
        console.log("WETH address from config:", weth);

        // Deploy BalanceManager
        uint256 feeMaker = 1; // Example fee maker value
        uint256 feeTaker = 5; // Example fee taker value
        uint256 lotSize = 1e18; // Example lot size
        uint256 maxOrderAmount = 5000e18; // Example max order amount

        balanceManager = new BalanceManager(owner, owner, feeMaker, feeTaker);
        // balanceManager = BalanceManager(0xE1349D2c44422b70C73BF767AFB58ae1C59cd1Fd);
        console.log("BalanceManager deployed at:", address(balanceManager));

        poolManager = new PoolManager(owner, address(balanceManager));
        // poolManager = PoolManager(0x3F401d161e328aECBF3E5786FCC457E6C85f71C6);
        console.log("PoolManager deployed at:", address(poolManager));

        router = new GTXRouter(address(poolManager), address(balanceManager));
        // router = GTXRouter(0xbDe5421D508C781c401E2af2101D74A23E39cBd6);
        console.log("GTXRouter deployed at:", address(router));

        Currency currency0 = Currency.wrap(address(weth));
        Currency currency1 = Currency.wrap(address(usdc));

        // Define a PoolKey with example values
        PoolKey memory poolKey = PoolKey({baseCurrency: currency0, quoteCurrency: currency1});

        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));
        poolManager.createPool(poolKey, lotSize, maxOrderAmount);

        IPoolManager.Pool memory pool = poolManager.getPool(poolKey);
        address orderBookAddress = address(pool.orderBook);
        console.log("OrderBook address:", orderBookAddress);

        vm.stopBroadcast();

        exportDeployments();
    }
}
