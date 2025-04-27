// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MockToken} from "../src/mocks/MockToken.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract DeployMocks is DeployHelpers {
    function run() public {
        uint256 deployerKey = getDeployerKey();
        console.log("Deployer Key:", deployerKey);
        vm.startBroadcast(deployerKey);

        MockToken usdc = new MockToken("Mock USDC", "USDC", 6);
        console.log("MockUSDC deployed at:", address(usdc));

        MockToken weth = new MockToken("Mock WETH", "WETH", 18);
        console.log("MockWETH deployed at:", address(weth));

        MockToken wbtc = new MockToken("Mock WBTC", "WBTC", 8);
        console.log("MockWBTC deployed at:", address(wbtc));

        MockToken pepe = new MockToken("Mock PEPE", "PEPE", 18);
        console.log("MockPEPE deployed at:", address(pepe));

        MockToken chainlink = new MockToken("Mock Chainlink", "LINK", 18);
        console.log("MockChainlink deployed at:", address(chainlink));

        vm.stopBroadcast();

        exportDeployments();
    }
}
