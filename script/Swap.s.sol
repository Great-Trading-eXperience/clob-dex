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
    // Swap type constants
    uint8 constant SWAP_WETH_TO_WBTC = 1;
    uint8 constant SWAP_WETH_TO_USDC = 2;
    uint8 constant SWAP_USDC_TO_WETH = 3;
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

    // Helper function to check and ensure liquidity exists for a swap
    function ensureLiquidity(address source, address destination, uint8 swapType) private {
        // Get the pool
        IPoolManager.Pool memory pool;
        if (swapType == SWAP_WETH_TO_WBTC) {
            // Not implemented in this example
        } else {
            // For WETH/USDC swaps
            pool = IPoolManager(poolManager).getPool(
                PoolKey({
                    baseCurrency: Currency.wrap(address(weth)),
                    quoteCurrency: Currency.wrap(address(usdc))
                })
            );
        }
        
        // Check liquidity based on swap type
        if (swapType == SWAP_WETH_TO_USDC) {
            // For WETH -> USDC
            IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(
                Currency.wrap(address(weth)), 
                Currency.wrap(address(usdc)), 
                IOrderBook.Side.BUY
            );
            
            if (bestBuy.price == 0 || bestBuy.volume == 0) {
                console.log("WARNING: No BUY liquidity found for WETH/USDC. Adding liquidity...");
                for (uint i = 0; i < 5; i++) {
                    uint128 price = uint128(1900e6 + i * 10e6); // 1900-1940 USDC per WETH
                    gtxRouter.placeOrderWithDeposit{gas: 1000000}(
                        pool,
                        price, // USDC per WETH
                        uint128(3e17),   // 0.3 WETH
                        IOrderBook.Side.BUY,
                        vm.addr(getDeployerKey())
                    );
                    console.log("Added BUY order at price %d USDC per WETH", price);
                }
                console.log("Added BUY liquidity for WETH/USDC pair");
            } else {
                console.log("Found BUY liquidity: %d USDC per WETH, volume: %d", bestBuy.price, bestBuy.volume);
            }
        } else if (swapType == SWAP_USDC_TO_WETH) {
            IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(
                Currency.wrap(address(weth)), 
                Currency.wrap(address(usdc)), 
                IOrderBook.Side.SELL
            );
            
            if (bestSell.price == 0 || bestSell.volume == 0) {
                console.log("WARNING: No SELL liquidity found for WETH/USDC. Adding liquidity...");
                // Add liquidity for USDC -> WETH
                gtxRouter.placeOrderWithDeposit{gas: 1000000}(
                    pool,
                    uint128(2000e6), // 2000 USDC per WETH
                    uint128(3e17),   // 0.3 WETH
                    IOrderBook.Side.SELL,
                    vm.addr(getDeployerKey())
                );
                console.log("Added SELL liquidity for WETH/USDC pair");
            } else {
                console.log("Found SELL liquidity: %d USDC per WETH, volume: %d", bestSell.price, bestSell.volume);
            }
        }
    }
    
    function run() external {
        uint8 swapType = SWAP_WETH_TO_USDC;
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
        weth.mint(owner, 1_000_000_000_000e8);
        usdc.mint(owner, 1_000_000_000_000e6);
        wbtc.mint(owner2, 1_000_000_000_000e18);
        weth.mint(owner2, 1_000_000_000_000e8);
        usdc.mint(owner2, 1_000_000_000_000e6);

        weth.approve(address(balanceManager), type(uint256).max);
        usdc.approve(address(balanceManager), type(uint256).max);
        wbtc.approve(address(balanceManager), type(uint256).max);

        // Determine source and destination tokens based on swap type
        address source;
        address destination;
        string memory swapDescription;
        
        if (swapType == SWAP_WETH_TO_WBTC) {
            source = address(weth);
            destination = address(wbtc);
            swapDescription = "WETH -> WBTC";
        } else if (swapType == SWAP_WETH_TO_USDC) {
            source = address(weth);
            destination = address(usdc);
            swapDescription = "WETH -> USDC";
        } else if (swapType == SWAP_USDC_TO_WETH) {
            source = address(usdc);
            destination = address(weth);
            swapDescription = "USDC -> WETH";
        } else {
            revert("Invalid swap type");
        }
        
        console.log("\nExecuting swap: %s", swapDescription);

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

        // Check and ensure liquidity exists for the swap
        console.log("\nChecking liquidity for %s swap...", swapDescription);
        ensureLiquidity(source, destination, swapType);

        vm.stopBroadcast();

        vm.startBroadcast(deployerPrivateKey2);

        // Approve tokens for second user
        MockToken(source).approve(address(balanceManager), type(uint256).max);

        // Set swap parameters based on swap type
        uint256 amountToSwap;
        uint256 minReceived;
        
        if (swapType == SWAP_WETH_TO_WBTC) {
            // Swap WETH -> WBTC
            amountToSwap = 1 * (10 ** MockToken(source).decimals()); // 1 WETH
            minReceived = (6 * (10 ** MockToken(destination).decimals())) / 100; // 0.06 WBTC
            console.log("Swapping %s WETH for at least %s WBTC", amountToSwap, minReceived);
        } 
        else if (swapType == SWAP_WETH_TO_USDC) {
            // Swap WETH -> USDC
            amountToSwap = 5e17; // 0.5 WETH (reduced from 1 WETH to match available liquidity)
            minReceived = 900 * (10 ** MockToken(destination).decimals()); // 900 USDC
            console.log("Swapping %s WETH for at least %s USDC", amountToSwap, minReceived);
        } 
        else if (swapType == SWAP_USDC_TO_WETH) {
            // Swap USDC -> WETH
            amountToSwap = 3000 * (10 ** MockToken(source).decimals()); // 3000 USDC
            minReceived = 1 * (10 ** MockToken(destination).decimals()); // 1 WETH
            console.log("Swapping %s USDC for at least %s WETH", amountToSwap, minReceived);
        }

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
