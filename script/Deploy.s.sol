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
import {Swap} from "./Swap.s.sol";
import {MockOrderBookFromRouter} from "./MockOrderBookFromRouter.s.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {console} from "forge-std/Script.sol";

contract Deploy is Script {
    DeployMocks public deployMocks;
    DeployContracts public deployContracts;
    
    function run() public {
        string memory chainId = vm.envString("CHAIN_ID");

        address[] memory tokens = new address[](5);

        usdc = vm.envAddress(string.concat("USDC_", chainId, "_ADDRESS"));

        tokens[0] = vm.envAddress(string.concat("WETH_", chainId, "_ADDRESS"));
        tokens[1] = vm.envAddress(string.concat("WBTC_", chainId, "_ADDRESS"));
        tokens[2] = vm.envAddress(string.concat("LINK_", chainId, "_ADDRESS"));
        tokens[3] = vm.envAddress(string.concat("TRUMP_", chainId, "_ADDRESS"));
        tokens[4] = vm.envAddress(string.concat("DOGE_", chainId, "_ADDRESS"));
        
        // If running on a local chain, no need to uncomment this code
        // Mock tokens, add addresses to the helperConfig,
        // deployMocks = new DeployMocks();
        // console.log("DeployMocks contract deployed at:", address(deployMocks));
        // deployMocks.run();

        // Deploy contracts
        deployContracts = new DeployContracts(usdc, tokens);

        (
            address balanceManager,
            address poolManager,
            address router
        ) = deployContracts.run();

        // Test deposit
        MockOrderBookFromRouter runFromRouter = new MockOrderBookFromRouter(
            balanceManager,
            poolManager,
            router,
            usdc,
            tokens
        );
        runFromRouter.run();

        // Execute swap script to test engine functionality in advance, including place order, place market order, swap, and match order
        Swap swap = new Swap(
            balanceManager,
            poolManager,
            router
        );
        swap.run();

        //if its called from testnet / mainnet
        // MockOrderBookFromRouter runFromRouter =
        //     new MockOrderBookFromRouter(address(0), address(0), address(0), usdc, tokens);
        // runFromRouter.run();
    }
}
