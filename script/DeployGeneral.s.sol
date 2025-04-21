/*
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

contract Deploy is Script {
    DeployMocks public deployMocks;
    DeployContracts public deployContracts;

    // address usdc;
    // address weth;
    // address wbtc;
    // address link;
    // address pepe;

    address usdc;
    address usdt;
    address dai;
    address weth;
    address wbtc;
    address link;
    address pepe;

    function run() public {
        string memory chainId = "31338";

        address[] memory tokens = new address[](6);
        // HelperConfig config = new HelperConfig();
        // (usdc, weth, wbtc, link, pepe) = config.activeNetworkConfig();

        // tokens[0] = weth;
        // tokens[1] = wbtc;
        // tokens[2] = link;
        // tokens[3] = pepe;

        // usdc = vm.envAddress(string.concat("USDC_", chainId, "_ADDRESS"));
        usdc = vm.envAddress("USDC_ADDRESS");

        console.log("USDC address from deployed contracts:", usdc);

        // tokens[0] = vm.envAddress(string.concat("USDT_", chainId, "_ADDRESS"));
        // tokens[1] = vm.envAddress(string.concat("DAI_", chainId, "_ADDRESS"));
        // tokens[2] = vm.envAddress(string.concat("WETH_", chainId, "_ADDRESS"));
        // tokens[3] = vm.envAddress(string.concat("WBTC_", chainId, "_ADDRESS"));
        // tokens[4] = vm.envAddress(string.concat("LINK_", chainId, "_ADDRESS"));
        // tokens[5] = vm.envAddress(string.concat("UNI_", chainId, "_ADDRESS"));
        // tokens[6] = vm.envAddress(string.concat("AAVE_", chainId, "_ADDRESS"));

        tokens[0] = vm.envAddress("WETH_ADDRESS");
        tokens[1] = vm.envAddress("WBTC_ADDRESS");
        tokens[2] = vm.envAddress("LINK_ADDRESS");
        tokens[3] = vm.envAddress("PEPE_ADDRESS");
        tokens[4] = vm.envAddress("TRUMP_ADDRESS");
        tokens[5] = vm.envAddress("DOGE_ADDRESS");

        // If running on a local chain, no need to uncomment this code
        // Mock tokens, add addresses to the helperConfig,
        // deployMocks = new DeployMocks();
        // console.log("DeployMocks contract deployed at:", address(deployMocks));
        // deployMocks.run();

        // Deploy contracts
        deployContracts = new DeployContracts(usdc, tokens);
        // console.log("DeployedContracts deployed at:", address(deployContracts));
        (
            address balanceManager,
            address poolManager,
            address router
        ) = deployContracts.run();

        // console.log("BALANCE_MANAGER_%s_ADDRESS=%s", chainId, address(balanceManager));
        // console.log("POOL_MANAGER_%s_ADDRESS=%s", chainId, address(poolManager));
        // console.log("ROUTER_%s_ADDRESS=%s", chainId, address(router));

        console.log("BALANCE_MANAGER_ADDRESS=%s", address(balanceManager));
        console.log("POOL_MANAGER_ADDRESS=%s", address(poolManager));
        console.log("ROUTER_ADDRESS=%s", address(router));

        // // Test deposit
        MockOrderBookFromRouter runFromRouter = new MockOrderBookFromRouter(
            balanceManager,
            poolManager,
            router,
            usdc,
            tokens
        );
        runFromRouter.run();

        //if its called from testnet / mainnet
        // MockOrderBookFromRouter runFromRouter =
        //     new MockOrderBookFromRouter(address(0), address(0), address(0), usdc, tokens);
        // runFromRouter.run();
    }
}
*/
