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

    function run() public {
        // deployMocks = new DeployMocks();
        // console.log("DeployMocks contract deployed at:", address(deployMocks));
        // deployMocks.run();

        // deployContracts = new DeployContracts();
        // console.log("DeployedContracts deployed at:", address(deployContracts));
        // deployContracts.run();

        MockOrderBookFromRouter runFromRouter = new MockOrderBookFromRouter();
        runFromRouter.run();
    }
}
