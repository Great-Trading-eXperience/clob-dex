// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {GTXRouter} from "../src/GTXRouter.sol";
import {BalanceManager} from "../src/BalanceManager.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {PoolKey} from "../src/libraries/Pool.sol";

contract Swap is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant WBTC_ADDRESS = "MOCK_TOKEN_WBTC";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;

    // Mock tokens
    MockToken weth;
    MockToken wbtc;
    MockToken usdc;

    function setUp() public {
        loadDeployments();
        loadContracts();
    }

    function loadContracts() private {
        // Load core contracts
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);

        // Load mock tokens
        weth = MockToken(deployed[WETH_ADDRESS].addr);
        wbtc = MockToken(deployed[WBTC_ADDRESS].addr);
        usdc = MockToken(deployed[USDC_ADDRESS].addr);
    }

    function run() external {
        uint256 deployerPrivateKey = getDeployerKey();
        uint256 deployerPrivateKey2 = getDeployerKey2();
        address owner = vm.addr(deployerPrivateKey);
        address owner2 = vm.addr(deployerPrivateKey2);

        vm.startBroadcast(deployerPrivateKey);

        console.log("wbtc", address(wbtc));
        console.log("weth", address(weth));
        console.log("usdc", address(usdc));

        // 1. Mint and approve tokens
        wbtc.mint(owner, 1_000_000_000_000e18);
        weth.mint(owner, 1_000_000_000_000e18);
        usdc.mint(owner, 1_000_000_000_000e18);
        wbtc.mint(owner2, 1_000_000_000_000e18);
        weth.mint(owner2, 1_000_000_000_000e18);
        usdc.mint(owner2, 1_000_000_000_000e18);

        weth.approve(address(balanceManager), type(uint256).max);
        usdc.approve(address(balanceManager), type(uint256).max);
        wbtc.approve(address(balanceManager), type(uint256).max);

        // WETH -> WBTC
        // address source = address(weth);
        // address destination = address(wbtc);

        // WETH -> USDC
        // address source = address(weth);
        // address destination = address(usdc);

        // USDC -> WETH
        address source = address(usdc);
        address destination = address(weth);

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
                baseCurrency: Currency.wrap(address(weth)),
                quoteCurrency: Currency.wrap(address(usdc))
            })
        );

        IPoolManager.Pool memory wbtcUsdcPool = IPoolManager(poolManager).getPool(
            PoolKey({
                baseCurrency: Currency.wrap(address(wbtc)),
                quoteCurrency: Currency.wrap(address(usdc))
            })
        );

        // Add liquidity to test WETH/WBTC where the exist pairs are WETH/USDC and WBTC/USDC
        // gtxRouter.placeOrderWithDeposit{gas: 1_000_000}(
        //     wethUsdcPool,
        //     uint128(2000e6),
        //     uint128(1e18),
        //     IOrderBook.Side.BUY,
        //     owner
        // );
        // gtxRouter.placeOrderWithDeposit{gas: 1_000_000}(
        //     wbtcUsdcPool,
        //     uint128(30_000e6),
        //     uint128(1e8),
        //     IOrderBook.Side.SELL,
        //     owner
        // );

        // Add liquidity to test WETH/USDC
        // gtxRouter.placeOrderWithDeposit{gas: 1000000}(
        //     wethUsdcPool,
        //     uint128(2000e8),
        //     uint128(3_000_000_000e6),
        //     IOrderBook.Side.BUY,
        //     owner
        // );

        // Add liquidity to test USDC/WETH
        gtxRouter.placeOrderWithDeposit{gas: 1000000}(
            wethUsdcPool,
            uint128(2000e8),
            uint128(3_000_000_000e18),
            IOrderBook.Side.SELL,
            owner
        );

        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey2);

        // Approve tokens for second user
        MockToken(source).approve(address(balanceManager), type(uint256).max);

        // Swap WETH -> WBTC
        // uint256 amountToSwap = 1 * (10 ** MockToken(source).decimals());
        // uint256 minReceived = (6 * (10 ** MockToken(destination).decimals())) / 100;

        // Swap WETH -> USDC
        // uint256 amountToSwap = 1 * (10 ** MockToken(source).decimals());
        // uint256 minReceived = 1800 * (10 ** MockToken(destination).decimals());

        // Swap USDC -> WETH
        uint256 amountToSwap = 3000 * (10 ** MockToken(source).decimals());
        uint256 minReceived = 1 * (10 ** MockToken(destination).decimals());

        uint256 received = gtxRouter.swap{gas: 10_000_000}(
            Currency.wrap(source),
            Currency.wrap(destination),
            amountToSwap,
            minReceived,
            2,
            owner2
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
