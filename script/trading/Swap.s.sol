// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {GTXRouter} from "../../src/core/GTXRouter.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {PoolManager} from "../../src/core/PoolManager.sol";
import {IPoolManager} from "../../src/core/interfaces/IPoolManager.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {PoolKey} from "../../src/core/libraries/Pool.sol";

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
       // Call the scenario you want to test
       swapUsdcToWeth(); // Change this to the scenario you want to run
   }

   function swapWethToWbtc() public {
       uint256 deployerPrivateKey = getDeployerKey();
       uint256 deployerPrivateKey2 = getDeployerKey2();
       address owner = vm.addr(deployerPrivateKey);
       address owner2 = vm.addr(deployerPrivateKey2);

       vm.startBroadcast(deployerPrivateKey);

       console.log("=== WETH -> WBTC Swap Scenario ===");
       console.log("wbtc", address(wbtc));
       console.log("weth", address(weth));
       console.log("usdc", address(usdc));

       // 1. Mint and approve tokens
       _mintAndApproveTokens(owner, owner2);

       address source = address(weth);
       address destination = address(wbtc);

       _logInitialBalances(source, destination, owner, owner2);

       // Get pools
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
       gtxRouter.placeLimitOrder{gas: 1_000_000}(
           wethUsdcPool,
           uint128(2000e6),
           uint128(1e18),
           IOrderBook.Side.BUY,
           IOrderBook.TimeInForce.GTC,
           uint128(2000e6)
       );
       gtxRouter.placeLimitOrder{gas: 1_000_000}(
           wbtcUsdcPool,
           uint128(30_000e6),
           uint128(1e8),
           IOrderBook.Side.SELL,
           IOrderBook.TimeInForce.GTC,
           uint128(1e8)
       );

       vm.stopBroadcast();

       vm.startBroadcast(deployerPrivateKey2);

       // Approve tokens for second user
       MockToken(source).approve(address(balanceManager), type(uint256).max);

       // Swap WETH -> WBTC
       uint256 amountToSwap = 1 * (10 ** MockToken(source).decimals());
       uint256 minReceived = (6 * (10 ** MockToken(destination).decimals())) / 100;

       uint256 received = gtxRouter.swap{gas: 10_000_000}(
           Currency.wrap(source),
           Currency.wrap(destination),
           amountToSwap,
           minReceived,
           2,
           owner2
       );

       _logSwapResults(source, destination, amountToSwap, received, owner, owner2);

       vm.stopBroadcast();
   }

   function swapWethToUsdc() public {
       uint256 deployerPrivateKey = getDeployerKey();
       uint256 deployerPrivateKey2 = getDeployerKey2();
       address owner = vm.addr(deployerPrivateKey);
       address owner2 = vm.addr(deployerPrivateKey2);

       vm.startBroadcast(deployerPrivateKey);

       console.log("=== WETH -> USDC Swap Scenario ===");
       console.log("wbtc", address(wbtc));
       console.log("weth", address(weth));
       console.log("usdc", address(usdc));

       // 1. Mint and approve tokens
       _mintAndApproveTokens(owner, owner2);

       address source = address(weth);
       address destination = address(usdc);

       _logInitialBalances(source, destination, owner, owner2);

       // Get pool
       IPoolManager.Pool memory wethUsdcPool = IPoolManager(poolManager).getPool(
           PoolKey({
               baseCurrency: Currency.wrap(address(weth)),
               quoteCurrency: Currency.wrap(address(usdc))
           })
       );

       // Add liquidity to test WETH/USDC
       gtxRouter.placeLimitOrder{gas: 1000000}(
           wethUsdcPool,
           uint128(2000e8),
           uint128(3_000_000_000e6),
           IOrderBook.Side.BUY,
           IOrderBook.TimeInForce.GTC,
           uint128(3_000_000_000e6)
       );

       vm.stopBroadcast();

       vm.startBroadcast(deployerPrivateKey2);

       // Approve tokens for second user
       MockToken(source).approve(address(balanceManager), type(uint256).max);

       // Swap WETH -> USDC
       uint256 amountToSwap = 1 * (10 ** MockToken(source).decimals());
       uint256 minReceived = 1800 * (10 ** MockToken(destination).decimals());

       uint256 received = gtxRouter.swap{gas: 10_000_000}(
           Currency.wrap(source),
           Currency.wrap(destination),
           amountToSwap,
           minReceived,
           2,
           owner2
       );

       _logSwapResults(source, destination, amountToSwap, received, owner, owner2);

       vm.stopBroadcast();
   }

   function swapUsdcToWeth() public {
       uint256 deployerPrivateKey = getDeployerKey();
       uint256 deployerPrivateKey2 = getDeployerKey2();
       address owner = vm.addr(deployerPrivateKey);
       address owner2 = vm.addr(deployerPrivateKey2);

       vm.startBroadcast(deployerPrivateKey);

       console.log("=== USDC -> WETH Swap Scenario ===");
       console.log("wbtc", address(wbtc));
       console.log("weth", address(weth));
       console.log("usdc", address(usdc));

       // 1. Mint and approve tokens
       _mintAndApproveTokens(owner, owner2);

       address source = address(usdc);
       address destination = address(weth);

       _logInitialBalances(source, destination, owner, owner2);

       // Get pool
       IPoolManager.Pool memory wethUsdcPool = IPoolManager(poolManager).getPool(
           PoolKey({
               baseCurrency: Currency.wrap(address(weth)),
               quoteCurrency: Currency.wrap(address(usdc))
           })
       );

       // Add liquidity to test USDC/WETH
       gtxRouter.placeLimitOrder{gas: 1000000}(
           wethUsdcPool,
           uint128(2000e8),
           uint128(3_000_000_000e18),
           IOrderBook.Side.SELL,
           IOrderBook.TimeInForce.GTC,
           uint128(3_000_000_000e18)
       );

       vm.stopBroadcast();

       vm.startBroadcast(deployerPrivateKey2);

       // Approve tokens for second user
       MockToken(source).approve(address(balanceManager), type(uint256).max);

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

       _logSwapResults(source, destination, amountToSwap, received, owner, owner2);

       vm.stopBroadcast();
   }

   function _mintAndApproveTokens(address owner, address owner2) private {
       wbtc.mint(owner, 1_000_000_000_000e18);
       weth.mint(owner, 1_000_000_000_000e18);
       usdc.mint(owner, 1_000_000_000_000e18);
       wbtc.mint(owner2, 1_000_000_000_000e18);
       weth.mint(owner2, 1_000_000_000_000e18);
       usdc.mint(owner2, 1_000_000_000_000e18);

       weth.approve(address(balanceManager), type(uint256).max);
       usdc.approve(address(balanceManager), type(uint256).max);
       wbtc.approve(address(balanceManager), type(uint256).max);
   }

   function _logInitialBalances(address source, address destination, address owner, address owner2) private view {
       console.log("\nInitial balances:");
       console.log("%s owner:", MockToken(source).symbol(), MockToken(source).balanceOf(owner));
       console.log(
           "%s owner:", MockToken(destination).symbol(), MockToken(destination).balanceOf(owner)
       );
       console.log("%s owner2:", MockToken(source).symbol(), MockToken(source).balanceOf(owner2));
       console.log(
           "%s owner2:", MockToken(destination).symbol(), MockToken(destination).balanceOf(owner2)
       );
   }

   function _logSwapResults(address source, address destination, uint256 amountToSwap, uint256 received, address owner, address owner2) private view {
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
   }
}
