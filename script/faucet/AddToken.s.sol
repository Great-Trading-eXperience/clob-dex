
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {DeployHelpers} from "../DeployHelpers.s.sol";
import {Faucet} from "../../src/faucet/Faucet.sol";
import {MockWETH} from "../../src/mocks/MockWETH.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

contract AddToken is DeployHelpers {
    // Contract address keys
    string constant FAUCET_ADDRESS = "PROXY_FAUCET";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    // Contracts
    Faucet faucet;
    MockWETH mockWETH;
    MockUSDC mockUSDC;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        // Load faucet contract
        faucet = Faucet(deployed[FAUCET_ADDRESS].addr);

        // Load mock tokens
        mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
        mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        setupTokens();

        vm.stopBroadcast();
    }

    function setupTokens() private {
        console.log("\n=== Setting up Faucet Tokens ===");

        uint256 availableTokensLength = faucet.getAvailableTokensLength();
        console.log("Previous Faucet available tokens length:", availableTokensLength);

        // Add tokens to faucet
        faucet.addToken(address(mockWETH));
        faucet.addToken(address(mockUSDC));

        availableTokensLength = faucet.getAvailableTokensLength();
        console.log("Current Faucet available tokens length:", availableTokensLength);

        // Mint initial tokens to faucet
        uint256 wethAmount = 1000e18; // 1000 WETH
        uint256 usdcAmount = 2_000_000e6; // 2,000,000 USDC

        mockWETH.mint(address(faucet), wethAmount);
        mockUSDC.mint(address(faucet), usdcAmount);

        console.log("Minted", wethAmount, "WETH to faucet");
        console.log("Minted", usdcAmount, "USDC to faucet");
    }
}