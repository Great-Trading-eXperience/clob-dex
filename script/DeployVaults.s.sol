// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockVault} from "../src/mocks/MockVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployVaults is Script {
    // Update these addresses with the output from DeployTokens script
    address WETH = address(0);
    address WBTC = address(0);
    address LINK = address(0);
    address UNI = address(0);
    address USDC = address(0);

    function run() public returns (address, address, address, address, address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        WETH = vm.envAddress("WETH_ADDRESS");
        WBTC = vm.envAddress("WBTC_ADDRESS");
        LINK = vm.envAddress("LINK_ADDRESS");
        UNI = vm.envAddress("UNI_ADDRESS");
        USDC = vm.envAddress("USDC_ADDRESS");

        MockVault aWETH = new MockVault(
            IERC20(WETH),
            "Aave Wrapped Ether",
            "aWETH"
        );

        MockVault aWBTC = new MockVault(
            IERC20(WBTC),
            "Aave Wrapped Bitcoin",
            "aWBTC"
        );

        MockVault aLINK = new MockVault(
            IERC20(LINK),
            "Aave Chainlink",
            "aLINK"
        );

        MockVault aUNI = new MockVault(
            IERC20(UNI),
            "Aave Uniswap",
            "aUNI"
        );

        MockVault aUSDC = new MockVault(
            IERC20(USDC),
            "Aave USD Coin",
            "aUSDC"
        );

        console.log("aWETH_ADDRESS=%s", address(aWETH));
        console.log("aWBTC_ADDRESS=%s", address(aWBTC));
        console.log("aLINK_ADDRESS=%s", address(aLINK));
        console.log("aUNI_ADDRESS=%s", address(aUNI));
        console.log("aUSDC_ADDRESS=%s", address(aUSDC));

        vm.stopBroadcast();

        return (address(aWETH), address(aWBTC), address(aLINK), address(aUNI), address(aUSDC));
    }
} 