// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockWBTC} from "../../src/mocks/MockWBTC.sol";

/**
 * @title DeployMockWBTC
 * @notice Deploy Mock WBTC token on Base Sepolia for testing
 * @dev This is for testnet only - use real WBTC on mainnet
 */
contract DeployMockWBTC is Script {
    function run() public returns (address wbtc) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n========== DEPLOYING MOCK WBTC ==========");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 84532, "Must be Base Sepolia (84532)");

        vm.startBroadcast(deployerPrivateKey);

        MockWBTC mockWBTC = new MockWBTC();
        wbtc = address(mockWBTC);

        console.log("MockWBTC deployed at:", wbtc);
        console.log("Deployer balance:", mockWBTC.balanceOf(deployer));
        console.log("Decimals:", mockWBTC.decimals());

        vm.stopBroadcast();

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("WBTC_BASE_SEPOLIA=%s", wbtc);
        console.log("\nNext: Deploy vault using VaultFactory.deploySimpleVault()");

        return wbtc;
    }
}
