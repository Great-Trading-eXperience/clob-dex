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
        deployContracts = new DeployContracts(usdc, tokens);
        // console.log("DeployedContracts deployed at:", address(deployContracts));
        (address balanceManager, address poolManager, address router) = deployContracts.run();

        // Test deposit
        MockOrderBookFromRouter runFromRouter =
            new MockOrderBookFromRouter(balanceManager, poolManager, router, usdc, tokens);
        runFromRouter.run();

        //if its called from testnet / mainnet
        // MockOrderBookFromRouter runFromRouter =
        //     new MockOrderBookFromRouter(address(0), address(0), address(0), usdc, tokens);
        // runFromRouter.run();
    }
}

// == Logs ==
//   DeployedContracts deployed at: 0xC7f2Cf4845C6db0e1a1e91ED41Bcd0FcC1b0E141
//   USDC address from deployed contracts: 0xa16E02E87b7454126E5E10d957A927A7F5B5d2be
//   BalanceManager deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
//   PoolManager deployed at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
//   GTXRouter deployed at: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9

// == Logs ==
//   USDC address from deployed contracts: 0x8dAF17A20c9DBA35f005b6324F493785D239719d
//   BalanceManager deployed at: 0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0
//   PoolManager deployed at: 0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82
//   GTXRouter deployed at: 0x9A676e781A523b5d0C0e43731313A708CB607508
//   USDC address from mock order from router: 0x56639dB16Ac50A89228026e42a316B30179A5376
