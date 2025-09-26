// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Faucet} from "../../src/faucet/Faucet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/DeployHelpers.s.sol";

contract DepositToken is DeployHelpers {
    // Contract address keys
    string constant FAUCET_ADDRESS = "PROXY_FAUCET";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    Faucet public faucet;
    IERC20 public weth;
    IERC20 public usdc;

    function setUp() public {
        loadDeployments();

        // Load deployed contract addresses
        address payable faucetProxy = payable(deployed[FAUCET_ADDRESS].addr);
        address wethAddress = deployed[WETH_ADDRESS].addr;
        address usdcAddress = deployed[USDC_ADDRESS].addr;

        // Initialize contract instances
        faucet = Faucet(faucetProxy);
        weth = IERC20(wethAddress);
        usdc = IERC20(usdcAddress);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        uint256 depositAmount = 1 * 10**24;
        address deployer = vm.addr(deployerPrivateKey);

        // Mint tokens to deployer
        MockToken(address(weth)).mint(deployer, depositAmount);
        MockToken(address(usdc)).mint(deployer, depositAmount);

        // Approve and deposit tokens
        weth.approve(address(faucet), depositAmount);
        usdc.approve(address(faucet), depositAmount);

        faucet.depositToken(address(weth), depositAmount);
        faucet.depositToken(address(usdc), depositAmount);

        console.log("Deposited", depositAmount, "WETH and USDC to faucet at", address(faucet));

        vm.stopBroadcast();
    }
}

interface MockToken is IERC20 {
    function mint(address to, uint256 amount) external;
}