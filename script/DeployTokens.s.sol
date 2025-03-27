// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

contract DeployTokens is Script {
    function run() public returns (address, address, address, address, address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        MockToken weth = new MockToken("Wrapped Ether", "WETH", 18);
        MockToken wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        MockToken link = new MockToken("Chainlink", "LINK", 18);
        MockToken uni = new MockToken("Uniswap", "UNI", 18);
        MockToken usdc = new MockToken("USD Coin", "USDC", 6);

        weth.mint(deployer, 1000000e18);
        wbtc.mint(deployer, 1000000e8);
        link.mint(deployer, 1000000e18);
        uni.mint(deployer, 1000000e18);
        usdc.mint(deployer, 1000000e6);

        console.log("WETH_ADDRESS=%s", address(weth));
        console.log("WBTC_ADDRESS=%s", address(wbtc));
        console.log("LINK_ADDRESS=%s", address(link));
        console.log("UNI_ADDRESS=%s", address(uni));
        console.log("USDC_ADDRESS=%s", address(usdc));

        vm.stopBroadcast();

        return (address(weth), address(wbtc), address(link), address(uni), address(usdc));
    }
} 