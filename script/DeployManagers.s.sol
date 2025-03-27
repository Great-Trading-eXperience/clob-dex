// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import "forge-std/Vm.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract DeployManagers is Script {
    using Strings for uint256;

    BalanceManager public balanceManager;
    PoolManager public poolManager;
    GTXRouter public router;

    address WETH = address(0);
    address WBTC = address(0);
    address LINK = address(0);
    address UNI = address(0);
    address USDC = address(0);

    function run() public returns (address, address, address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 deployerPrivateKey2 = vm.envUint("PRIVATE_KEY_2");

        address owner = vm.addr(deployerPrivateKey);
        address owner2 = vm.addr(deployerPrivateKey2);

        WETH = vm.envAddress("WETH_ADDRESS");
        WBTC = vm.envAddress("WBTC_ADDRESS");
        LINK = vm.envAddress("LINK_ADDRESS");
        UNI = vm.envAddress("UNI_ADDRESS");
        USDC = vm.envAddress("USDC_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        uint256 feeMaker = 1; // Example fee maker value
        uint256 feeTaker = 1; // Example fee taker value

        balanceManager = new BalanceManager(owner, owner, feeMaker, feeTaker);
        // console.log("BALANCE_MANAGER_ADDRESS=%s", address(balanceManager));

        poolManager = new PoolManager(owner, address(balanceManager));
        // console.log("POOL_MANAGER_ADDRESS=%s", address(poolManager));
        router = new GTXRouter(address(poolManager), address(balanceManager));
        // console.log("ROUTER_ADDRESS=%s", address(router));

        MockToken(WETH).approve(address(balanceManager), type(uint256).max);
        MockToken(WBTC).approve(address(balanceManager), type(uint256).max);
        MockToken(LINK).approve(address(balanceManager), type(uint256).max);
        MockToken(UNI).approve(address(balanceManager), type(uint256).max);
        MockToken(USDC).approve(address(balanceManager), type(uint256).max);

        vm.stopBroadcast();
        vm.startBroadcast(deployerPrivateKey2);

        MockToken(WETH).approve(address(balanceManager), type(uint256).max);
        MockToken(WBTC).approve(address(balanceManager), type(uint256).max);
        MockToken(LINK).approve(address(balanceManager), type(uint256).max);
        MockToken(UNI).approve(address(balanceManager), type(uint256).max);
        MockToken(USDC).approve(address(balanceManager), type(uint256).max);

        vm.stopBroadcast();
        vm.startBroadcast(deployerPrivateKey);

        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));

        vm.stopBroadcast();

        return (
            address(balanceManager),
            address(poolManager),
            address(router)
        );
    }
}
