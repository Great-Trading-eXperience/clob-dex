// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";

contract DeployMocks is DeployHelpers {
    MockUSDC public mockUSDC;
    MockWETH public mockWeth;

    function run() public {
        uint256 deployerKey = getDeployerKey();
        console.log("Deployer Key:", deployerKey);
        vm.startBroadcast(deployerKey);

        mockUSDC = new MockUSDC();
        console.log("MockUSDC deployed at:", address(mockUSDC));

        mockWeth = new MockWETH();
        console.log("MockWETH deployed at:", address(mockWeth));

        vm.stopBroadcast();

        exportDeployments();
    }
}
