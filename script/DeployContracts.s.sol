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
    address weth;
    address wbtc;
    address link;
    address pepe;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        address[] memory tokens = new address[](4);
        HelperConfig config = new HelperConfig();
        (usdc, weth, wbtc, link, pepe) = config.activeNetworkConfig();

        console.log("USDC address from config:", usdc);

        tokens[0] = weth;
        tokens[1] = wbtc;
        tokens[2] = link;
        tokens[3] = pepe;

        // uint256 feeMaker = 1; // Example fee maker value
        // uint256 feeTaker = 5; // Example fee taker value
        uint256 lotSize = 1e18; // Example lot size
        uint256 maxOrderAmount = 5000e18; // Example max order amount

        // balanceManager = new BalanceManager(owner, owner, feeMaker, feeTaker);
        balanceManager = BalanceManager(0x9B4fD469B6236c27190749bFE3227b85c25462D7);
        console.log("BalanceManager deployed at:", address(balanceManager));

        // poolManager = new PoolManager(owner, address(balanceManager));
        poolManager = PoolManager(0x35234957aC7ba5d61257d72443F8F5f0C431fD00);
        console.log("PoolManager deployed at:", address(poolManager));

        // router = new GTXRouter(address(poolManager), address(balanceManager));
        router = GTXRouter(0xed2582315b355ad0FFdF4928Ca353773c9a588e3);
        console.log("GTXRouter deployed at:", address(router));

        Currency quoteCurrency = Currency.wrap(address(usdc));

        // Define a PoolKey with example values

        // balanceManager.setAuthorizedOperator(address(poolManager), true);
        // balanceManager.transferOwnership(address(poolManager));
        // poolManager.setRouter(address(router));

        uint256 tokensLength = tokens.length;

        for (uint256 i = 0; i < tokensLength; ++i) {
            Currency baseCurrency = Currency.wrap(tokens[i]);
            PoolKey memory poolKey =
                PoolKey({baseCurrency: baseCurrency, quoteCurrency: quoteCurrency});
            poolManager.createPool(poolKey, lotSize, maxOrderAmount);
        }

        vm.stopBroadcast();

        exportDeployments();
    }
}
