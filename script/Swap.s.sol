// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {GTXRouter} from "../src/GTXRouter.sol";
import {BalanceManager} from "../src/BalanceManager.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {PoolKey} from "../src/libraries/Pool.sol";

contract Swap is Script {
    string chainId;

    address balanceManager;
    address poolManager;
    address gtxRouter;
    address weth;
    address wbtc;
    address usdc;

    // constructor(address _balanceManager, address _poolManager, address _gtxRouter) {
    //     balanceManager = _balanceManager;
    //     poolManager = _poolManager;
    //     gtxRouter = _gtxRouter;

    //     setUp();
    // }

    function setUp() public {
        // Get deployed contract addresses from environment
        chainId = vm.envString("CHAIN_ID");
        // balanceManager = vm.envAddress(string.concat("BALANCE_MANAGER_", chainId, "_ADDRESS"));
        // poolManager = vm.envAddress(string.concat("POOL_MANAGER_", chainId, "_ADDRESS"));
        // gtxRouter = vm.envAddress(string.concat("ROUTER_", chainId, "_ADDRESS"));

        // Get token addresses
        wbtc = vm.envAddress(string.concat("WBTC_", chainId, "_ADDRESS"));
        weth = vm.envAddress(string.concat("WETH_", chainId, "_ADDRESS"));
        usdc = vm.envAddress(string.concat("USDC_", chainId, "_ADDRESS"));

        // wbtc = address(new MockToken("WBTC", "WBTC", 18));
        // weth = address(new MockToken("WETH", "WETH", 18));
        // usdc = address(new MockToken("USDC", "USDC", 18));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 deployerPrivateKey2 = vm.envUint("PRIVATE_KEY_2");
        address owner = vm.addr(deployerPrivateKey);
        address owner2 = vm.addr(deployerPrivateKey2);

        vm.startBroadcast(deployerPrivateKey);

        console.log("wbtc", wbtc);
        console.log("weth", weth);
        console.log("usdc", usdc);

        // 1. Mint and approve tokens
        MockToken(wbtc).mint(owner, 1_000_000_000_000e18);
        MockToken(weth).mint(owner, 1_000_000_000_000e18);
        MockToken(usdc).mint(owner, 1_000_000_000_000e18);
        MockToken(wbtc).mint(owner2, 1_000_000_000_000e18);
        MockToken(weth).mint(owner2, 1_000_000_000_000e18);
        MockToken(usdc).mint(owner2, 1_000_000_000_000e18);

        MockToken(weth).approve(balanceManager, type(uint256).max);
        MockToken(usdc).approve(balanceManager, type(uint256).max);
        MockToken(wbtc).approve(balanceManager, type(uint256).max);

        // WETH -> WBTC
        address source = weth;
        address destination = wbtc;

        // WETH -> USDC
        // address source = weth;
        // address destination = wbtc;

        console.log("\nInitial balances:");
        console.log("%s owner:", MockToken(source).symbol(), MockToken(source).balanceOf(owner));
        console.log(
            "%s owner:", MockToken(destination).symbol(), MockToken(destination).balanceOf(owner)
        );
        console.log("%s owner2:", MockToken(source).symbol(), MockToken(source).balanceOf(owner2));
        console.log(
            "%s owner2:", MockToken(destination).symbol(), MockToken(destination).balanceOf(owner2)
        );

        // Provide liquidity

        IPoolManager.Pool memory wethUsdcPool = IPoolManager(poolManager).getPool(
            PoolKey({
                baseCurrency: Currency.wrap(weth),
                quoteCurrency: Currency.wrap(usdc)
            })
        );

        IPoolManager.Pool memory wbtcUsdcPool = IPoolManager(poolManager).getPool(
            PoolKey({
                baseCurrency: Currency.wrap(wbtc),
                quoteCurrency: Currency.wrap(usdc)
            })
        );

        // Add liquidity to test WETH/WBTC where the exist pairs are WETH/USDC and WBTC/USDC
        GTXRouter(gtxRouter).placeOrderWithDeposit{gas: 1_000_000}(
            wethUsdcPool,
            uint128(2000e6),
            uint128(1e18),
            IOrderBook.Side.BUY,
            owner
        );
        GTXRouter(gtxRouter).placeOrderWithDeposit{gas: 1_000_000}(
            wbtcUsdcPool,
            uint128(30_000e6),
            uint128(1e8),
            IOrderBook.Side.SELL,
            owner
        );

        // Add liquidity to test WETH/USDC
        // GTXRouter(gtxRouter).placeOrderWithDeposit{gas: 1000000}(
        //     Currency.wrap(weth),
        //     Currency.wrap(usdc),
        //     Price.wrap(2000e8),
        //     Quantity.wrap(3_000_000_000e6),
        //     Side.BUY,
        //     owner
        // );

        // Add liquidity to test USDC/WETH
        // GTXRouter(gtxRouter).placeOrderWithDeposit{gas: 1000000}(
        //     Currency.wrap(weth),
        //     Currency.wrap(usdc),
        //     Price.wrap(2000e8),
        //     Quantity.wrap(3_000_000_000e18),
        //     Side.SELL,
        //     owner
        // );

        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey2);

        if (keccak256(abi.encodePacked(chainId)) != keccak256(abi.encodePacked("GTX"))) {
            MockToken(wbtc).approve(balanceManager, type(uint256).max);
            MockToken(usdc).approve(balanceManager, type(uint256).max);
            MockToken(weth).approve(balanceManager, type(uint256).max);
        }

        // Swap WETH -> WBTC
        uint256 amountToSwap = 1 * (10 ** MockToken(source).decimals());
        uint256 minReceived = (6 * (10 ** MockToken(destination).decimals())) / 100;

        // Swap WETH -> USDC
        // uint256 amountToSwap = 1 * (10 ** MockToken(source).decimals());
        // uint256 minReceived = 1800 * (10 ** MockToken(destination).decimals());

        // Swap USDC -> WETH
        // uint256 amountToSwap = 3000 * (10 ** MockToken(source).decimals());
        // uint256 minReceived = 1 * (10 ** MockToken(destination).decimals());

        uint256 received = GTXRouter(gtxRouter).swap{gas: 10_000_000}(
            Currency.wrap(source), Currency.wrap(destination), amountToSwap, minReceived, 2, owner2
        );

        console.log("\nSwap complete!");
        console.log("%s spent:", MockToken(source).symbol(), amountToSwap);
        console.log("%s received:", MockToken(destination).symbol(), received);

        console.log("\nFinal balances:");
        console.log("%s owner:", MockToken(source).symbol(), MockToken(source).balanceOf(owner));
        console.log(
            "%s owner:", MockToken(destination).symbol(), MockToken(destination).balanceOf(owner)
        );
        console.log("%s owner2:", MockToken(source).symbol(), MockToken(source).balanceOf(owner2));
        console.log(
            "%s owner2:", MockToken(destination).symbol(), MockToken(destination).balanceOf(owner2)
        );

        vm.stopBroadcast();
    }
}
