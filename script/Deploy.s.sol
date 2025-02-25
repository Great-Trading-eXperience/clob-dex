// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import "../src/mocks/MockWETH.sol";
import "../src/mocks/MockUSDC.sol";
import {DeployMocks} from "./DeployMocks.s.sol";
import {DeployContracts} from "./DeployContracts.s.sol";
import {MockOrderBookFromRouter} from "./MockOrderBookFromRouter.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

contract Deploy {
    DeployMocks public deployMocks;
    DeployContracts public deployContracts;

    address usdc;
    address weth;
    address wbtc;
    address link;
    address pepe;

    function run() public {
        address[] memory tokens = new address[](4);
        HelperConfig config = new HelperConfig();
        (usdc, weth, wbtc, link, pepe) = config.activeNetworkConfig();

        console.log("USDC address from deployed contracts:", usdc);

        tokens[0] = weth;
        tokens[1] = wbtc;
        tokens[2] = link;
        tokens[3] = pepe;

        // If running on a local chain, no need to uncomment this code
        // Mock tokens, add addresses to the helperConfig,
        // deployMocks = new DeployMocks();
        // console.log("DeployMocks contract deployed at:", address(deployMocks));
        // deployMocks.run();

        // Deploy contracts
        // deployContracts = new DeployContracts(usdc, tokens);
        // // console.log("DeployedContracts deployed at:", address(deployContracts));
        // (address balanceManager, address poolManager, address router) = deployContracts.run();

        // // Test deposit
        // MockOrderBookFromRouter runFromRouter =
        //     new MockOrderBookFromRouter(balanceManager, poolManager, router, usdc, tokens);
        // runFromRouter.run();

        //if its called from testnet / mainnet
        MockOrderBookFromRouter runFromRouter =
            new MockOrderBookFromRouter(address(0), address(0), address(0), usdc, tokens);
        runFromRouter.run();
    }
}
