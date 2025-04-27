// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BalanceManager} from "../src/BalanceManager.sol";
import {GTXRouter} from "../src/GTXRouter.sol";

import {OrderBook} from "../src/OrderBook.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {PoolKey} from "../src/libraries/Pool.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Test, console} from "forge-std/Test.sol";

import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolHelper} from "./helpers/PoolHelper.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract SwapTest is Test, PoolHelper {
    // Contracts
    BalanceManager public balanceManager;
    PoolManager public poolManager;
    GTXRouter public router;

    // Mock tokens
    MockToken public weth;
    MockToken public wbtc;
    MockToken public usdc;

    // Test users
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address david = address(0x4);

    address owner = address(0x5);
    address feeCollector = address(0x6);

    // Define fee structure - modifiable for different test scenarios
    uint256 feeMaker = 10; // 0.1% as basis points (10/10000)
    uint256 feeTaker = 20; // 0.2% as basis points (20/10000)
    uint256 lotSize = 1e18;
    uint256 maxOrderAmount = 500e18;
    uint256 feeUnit = 1000;

    // Test constants
    uint256 public constant INITIAL_BALANCE = 1_000_000_000_000_000_000e18;

    // Trading rules
    IOrderBook.TradingRules rules;

    // Pool-related variables
    mapping(string => address) poolOrderBooks;
    mapping(string => IPoolManager.Pool) pools;

    function setUp() public {
        // Deploy mock tokens
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        wbtc = new MockToken("Wrapped Bitcoin", "WBTC", 8);
        usdc = new MockToken("USD Coin", "USDC", 6);

        // Set environment variables for tokens
        vm.setEnv("CHAIN_ID", "GTX_TEST");
        vm.setEnv("WETH_GTX_TEST_ADDRESS", addressToString(address(weth)));
        vm.setEnv("WBTC_GTX_TEST_ADDRESS", addressToString(address(wbtc)));
        vm.setEnv("USDC_GTX_TEST_ADDRESS", addressToString(address(usdc)));
        vm.setEnv("PRIVATE_KEY", uint256ToString(uint256(uint160(alice))));
        vm.setEnv("PRIVATE_KEY_2", uint256ToString(uint256(uint160(bob))));

        // Fund test accounts
        dealTokens(alice);
        dealTokens(bob);
        dealTokens(charlie);
        dealTokens(david);

        // Set up trading rules
        rules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH (18 decimals)
            minAmountMovement: 1e13, // 0.00001 ETH (18 decimals)
            minOrderSize: 1e4, // 0.01 USDC (6 decimals)
            minPriceMovement: 1e4 // 0.01 USDC (6 decimals)
        });

        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy, address balanceManagerBeacon) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeCollector, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy, address poolManagerBeacon) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        (BeaconProxy routerProxy, address gtxRouterBeacon) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(GTXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        router = GTXRouter(address(routerProxy));

        // Set up permissions and connections
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));
        vm.stopPrank();

        // Approve tokens for all users
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;

        for (uint256 i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            weth.approve(address(balanceManager), type(uint256).max);
            wbtc.approve(address(balanceManager), type(uint256).max);
            usdc.approve(address(balanceManager), type(uint256).max);
            vm.stopPrank();
        }

        // Create all required pools
        createAllPools();
    }

    function createAllPools() internal {
        vm.startPrank(owner);

        rules.minTradeAmount = uint128(10 ** (weth.decimals() / 2));
        rules.minAmountMovement = uint128(10 ** (weth.decimals() / 2));
        rules.minOrderSize = uint128(10 ** (weth.decimals() / 2));

        // Create WETH/USDC pool
        poolManager.createPool(Currency.wrap(address(weth)), Currency.wrap(address(usdc)), rules);

        // Get the orderbook address for WETH/USDC pool
        PoolKey memory wethUsdcKey =
            poolManager.createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)));
        address wethUsdcOrderBook = address(poolManager.getPool(wethUsdcKey).orderBook);
        poolOrderBooks["WETH/USDC"] = wethUsdcOrderBook;
        pools["WETH/USDC"] = _getPool(poolManager, Currency.wrap(address(weth)), Currency.wrap(address(usdc)));

        rules.minTradeAmount = uint128(10 ** (weth.decimals() / 2));
        rules.minAmountMovement = uint128(10 ** (weth.decimals() / 2));
        rules.minOrderSize = uint128(10 ** (weth.decimals() / 2));

        // Create WBTC/USDC pool
        poolManager.createPool(
            Currency.wrap(address(wbtc)),
            Currency.wrap(address(usdc)),
            IOrderBook.TradingRules({
                minTradeAmount: 1e3, // 0.00001 BTC (8 decimals)
                minAmountMovement: 1e3, // 0.00001 BTC (8 decimals)
                minOrderSize: 1e4, // 0.01 USDC (6 decimals)
                minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
            })
        );

        // Get the orderbook address for WBTC/USDC pool
        PoolKey memory wbtcUsdcKey =
            poolManager.createPoolKey(Currency.wrap(address(wbtc)), Currency.wrap(address(usdc)));
        address wbtcUsdcOrderBook = address(poolManager.getPool(wbtcUsdcKey).orderBook);
        poolOrderBooks["WBTC/USDC"] = wbtcUsdcOrderBook;
        pools["WBTC/USDC"] = _getPool(poolManager, Currency.wrap(address(wbtc)), Currency.wrap(address(usdc)));

        // Try to create WETH/WBTC pool (might not be needed depending on your tests)
        try poolManager.createPool(Currency.wrap(address(weth)), Currency.wrap(address(wbtc)), rules) {
            // Get the orderbook address for WETH/WBTC pool
            PoolKey memory wethWbtcKey =
                poolManager.createPoolKey(Currency.wrap(address(weth)), Currency.wrap(address(wbtc)));
            address wethWbtcOrderBook = address(poolManager.getPool(wethWbtcKey).orderBook);
            poolOrderBooks["WETH/WBTC"] = wethWbtcOrderBook;
            pools["WETH/WBTC"] = _getPool(poolManager, Currency.wrap(address(weth)), Currency.wrap(address(wbtc)));
            console.log("Created WETH/WBTC pool");
        } catch {
            console.log("WETH/WBTC pool creation failed or already exists");
        }

        vm.stopPrank();
    }

    function dealTokens(
        address user
    ) private {
        vm.startPrank(user);
        weth.mint(user, INITIAL_BALANCE);
        wbtc.mint(user, INITIAL_BALANCE);
        usdc.mint(user, INITIAL_BALANCE);
        vm.stopPrank();
    }

    function logBalance(string memory name, address user) internal view {
        console.log("%s balances:", name);
        console.log("  WETH: %s", weth.balanceOf(user));
        console.log("  WBTC: %s", wbtc.balanceOf(user));
        console.log("  USDC: %s", usdc.balanceOf(user));
        console.log("  WETH (protocol): %s", balanceManager.getBalance(user, Currency.wrap(address(weth))));
        console.log("  WBTC (protocol): %s", balanceManager.getBalance(user, Currency.wrap(address(wbtc))));
        console.log("  USDC (protocol): %s", balanceManager.getBalance(user, Currency.wrap(address(usdc))));

        // Log locked balances for all pools if orderbook exists
        if (poolOrderBooks["WETH/USDC"] != address(0)) {
            console.log(
                "  WETH locked (WETH/USDC): %s",
                balanceManager.getLockedBalance(user, poolOrderBooks["WETH/USDC"], Currency.wrap(address(weth)))
            );
            console.log(
                "  USDC locked (WETH/USDC): %s",
                balanceManager.getLockedBalance(user, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)))
            );
        }

        if (poolOrderBooks["WBTC/USDC"] != address(0)) {
            console.log(
                "  WBTC locked (WBTC/USDC): %s",
                balanceManager.getLockedBalance(user, poolOrderBooks["WBTC/USDC"], Currency.wrap(address(wbtc)))
            );
            console.log(
                "  USDC locked (WBTC/USDC): %s",
                balanceManager.getLockedBalance(user, poolOrderBooks["WBTC/USDC"], Currency.wrap(address(usdc)))
            );
        }

        if (poolOrderBooks["WETH/WBTC"] != address(0)) {
            console.log(
                "  WETH locked (WETH/WBTC): %s",
                balanceManager.getLockedBalance(user, poolOrderBooks["WETH/WBTC"], Currency.wrap(address(weth)))
            );
            console.log(
                "  WBTC locked (WETH/WBTC): %s",
                balanceManager.getLockedBalance(user, poolOrderBooks["WETH/WBTC"], Currency.wrap(address(wbtc)))
            );
        }
    }

    function testWethToWbtcSwap() public {
        console.log("\n=== WETH TO WBTC SWAP TEST ===");

        // Get initial balances for all participants
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);
        uint256 aliceInitialWbtcBalance = wbtc.balanceOf(alice);
        uint256 aliceInitialUsdcBalance = usdc.balanceOf(alice);
        uint256 bobInitialWethBalance = weth.balanceOf(bob);
        uint256 bobInitialWbtcBalance = wbtc.balanceOf(bob);
        uint256 bobInitialUsdcBalance = usdc.balanceOf(bob);

        console.log("--- Initial Balances ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);

        // Add liquidity for WETH/USDC and WBTC/USDC pools
        vm.startPrank(alice);
        // For WETH -> USDC, we need a SELL order to provide WETH
        console.log("--- Alice places sell order at 2000 USDC per WETH ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            2000e6, // 1 ETH = 2000 USDC
            10e18, // 10 ETH
            IOrderBook.Side.SELL,
            alice
        );

        // For USDC -> WBTC, we need a SELL order to provide WBTC
        console.log("--- Alice places sell order at 30000 USDC per WBTC ---");
        router.placeOrderWithDeposit(
            pools["WBTC/USDC"],
            30_000e6, // 1 BTC = 30,000 USDC
            1e8, // 1 BTC
            IOrderBook.Side.SELL,
            alice
        );
        vm.stopPrank();

        // Check balances after liquidity provision
        console.log("\n--- Balances After Liquidity Provision ---");
        logBalance("Alice", alice);

        // Verify Alice's WETH was locked
        uint256 aliceLockedWeth =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WETH/USDC"], Currency.wrap(address(weth)));
        assertEq(aliceLockedWeth, 10e18, "Alice's locked WETH incorrect");

        // Verify Alice's WBTC was locked
        uint256 aliceLockedWbtc =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WBTC/USDC"], Currency.wrap(address(wbtc)));
        assertEq(aliceLockedWbtc, 1e8, "Alice's locked WBTC incorrect");

        // Bob performs a swap WETH -> WBTC
        vm.startPrank(bob);
        console.log("\n--- Bob swaps 1 WETH for WBTC ---");
        uint256 wethToSwap = 1e18; // 1 ETH
        uint256 minWbtcReceived = 6e6; // 0.06 BTC (considering price ratio and possible slippage)

        uint256 received = router.swap(
            Currency.wrap(address(weth)),
            Currency.wrap(address(wbtc)),
            wethToSwap,
            minWbtcReceived,
            2, // max hops
            bob
        );
        vm.stopPrank();

        // Check final balances
        console.log("\n--- Final Balances After Swap ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);

        // Calculate expected values for verification
        // 1 ETH = 2000 USDC, 30000 USDC = 1 BTC, so 1 ETH ≈ 0.0667 BTC
        uint256 expectedUsdc = 2000e6; // From 1 ETH
        uint256 expectedWbtc = (expectedUsdc * 1e8) / 30_000e6; // Convert to WBTC

        // Verify Bob's balances
        uint256 bobFinalWethBalance = weth.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(weth)));
        uint256 bobFinalWbtcBalance = wbtc.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(wbtc)));

        assertEq(bobFinalWethBalance, bobInitialWethBalance - wethToSwap, "Bob's WETH not deducted correctly");
        assertEq(bobFinalWbtcBalance, bobInitialWbtcBalance + received, "Bob's WBTC not received correctly");
        assertApproxEqAbs(received, expectedWbtc, 100, "Bob received unexpected amount of WBTC");
        assertTrue(received >= minWbtcReceived, "Received less than minimum required");

        console.log("\n--- Swap Results ---");
        console.log("Bob spent: %s WETH", wethToSwap);
        console.log("Bob received: %s WBTC", received);
        console.log("Expected (ideal): %s WBTC", expectedWbtc);
    }

    function testWethToUsdcSwap() public {
        console.log("\n=== WETH TO USDC SWAP TEST ===");

        // Get initial balances
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);
        uint256 aliceInitialUsdcBalance = usdc.balanceOf(alice);
        uint256 bobInitialWethBalance = weth.balanceOf(bob);
        uint256 bobInitialUsdcBalance = usdc.balanceOf(bob);

        console.log("--- Initial Balances ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);

        // Add liquidity for WETH/USDC pool - for WETH->USDC we need someone to buy WETH with USDC
        vm.startPrank(alice);
        console.log("--- Alice places BUY order at 2000 USDC per WETH ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            2000e6, // 1 ETH = 2000 USDC
            10e18, // 10 ETH
            IOrderBook.Side.BUY,
            alice
        );
        vm.stopPrank();

        // Check locked balances after liquidity provision
        uint256 aliceLockedUsdc =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)));

        assertEq(aliceLockedUsdc, 20_000e6, "Alice's locked USDC incorrect"); // 10 ETH * 2000 USDC/ETH

        console.log("\n--- Balances After Liquidity Provision ---");
        logBalance("Alice", alice);

        // Bob performs a swap WETH -> USDC (selling ETH to buy USDC)
        vm.startPrank(bob);
        console.log("\n--- Bob swaps 1 WETH for USDC ---");
        uint256 wethToSwap = 1e18; // 1 ETH
        uint256 minUsdcReceived = 1800e6; // 1800 USDC (with 10% slippage)

        uint256 received = router.swap(
            Currency.wrap(address(weth)),
            Currency.wrap(address(usdc)),
            wethToSwap,
            minUsdcReceived,
            1, // direct swap
            bob
        );
        vm.stopPrank();

        // Check final balances
        console.log("\n--- Final Balances After Swap ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);

        // Verify Bob's balances
        uint256 bobFinalWethBalance = weth.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(weth)));
        uint256 bobFinalUsdcBalance = usdc.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(usdc)));

        assertEq(bobFinalWethBalance, bobInitialWethBalance - wethToSwap, "Bob's WETH not deducted correctly");
        assertEq(bobFinalUsdcBalance, bobInitialUsdcBalance + received, "Bob's USDC not received correctly");

        // Expected amount should be around 2000 USDC (may be affected by fees)
        uint256 expectedUsdcReceived = 2000e6;
        uint256 expectedWithTakerFee = (expectedUsdcReceived * (feeUnit - feeTaker)) / feeUnit;
        assertApproxEqAbs(received, expectedWithTakerFee, 100, "Bob received unexpected amount of USDC");
        assertTrue(received >= minUsdcReceived, "Received less than minimum required");

        console.log("\n--- Swap Results ---");
        console.log("Bob spent: %s WETH", wethToSwap);
        console.log("Bob received: %s USDC", received);
        console.log("Expected (ideal): %s USDC", expectedUsdcReceived);
        console.log("Expected (with fees): %s USDC", expectedWithTakerFee);
    }

    function testUsdcToWethSwap() public {
        console.log("\n=== USDC TO WETH SWAP TEST ===");

        // Get initial balances
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);
        uint256 aliceInitialUsdcBalance = usdc.balanceOf(alice);
        uint256 charlieInitialWethBalance = weth.balanceOf(charlie);
        uint256 charlieInitialUsdcBalance = usdc.balanceOf(charlie);

        console.log("--- Initial Balances ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);

        // Add liquidity for USDC/WETH pool
        vm.startPrank(alice);
        // For USDC -> WETH, we need a SELL order to provide WETH
        console.log("--- Alice places sell order at 2000 USDC per WETH ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            2000e6, // 1 ETH = 2000 USDC
            10e18, // 10 ETH
            IOrderBook.Side.SELL,
            alice
        );
        vm.stopPrank();

        // Check locked balances after liquidity provision
        uint256 aliceLockedWeth =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WETH/USDC"], Currency.wrap(address(weth)));

        assertEq(aliceLockedWeth, 10e18, "Alice's locked WETH incorrect");

        console.log("\n--- Balances After Liquidity Provision ---");
        logBalance("Alice", alice);

        // Charlie performs a swap USDC -> WETH
        vm.startPrank(charlie);
        console.log("\n--- Charlie swaps 3000 USDC for WETH ---");
        uint256 usdcToSwap = 3000e6; // 3000 USDC
        uint256 minWethReceived = 1.4e18; // 1.4 ETH (with slippage)

        uint256 received = router.swap(
            Currency.wrap(address(usdc)),
            Currency.wrap(address(weth)),
            usdcToSwap,
            minWethReceived,
            1, // direct swap
            charlie
        );
        vm.stopPrank();

        // Check final balances
        console.log("\n--- Final Balances After Swap ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);

        // Verify Charlie's balances
        uint256 charlieFinalUsdcBalance =
            usdc.balanceOf(charlie) + balanceManager.getBalance(charlie, Currency.wrap(address(usdc)));
        uint256 charlieFinalWethBalance =
            weth.balanceOf(charlie) + balanceManager.getBalance(charlie, Currency.wrap(address(weth)));

        assertEq(
            charlieFinalUsdcBalance, charlieInitialUsdcBalance - usdcToSwap, "Charlie's USDC not deducted correctly"
        );
        assertEq(charlieFinalWethBalance, charlieInitialWethBalance + received, "Charlie's WETH not received correctly");

        // Expected amount should be around 1.5 ETH (3000 USDC / 2000 USDC/ETH)
        uint256 expectedWethReceived = (usdcToSwap * 1e18) / 2000e6;
        uint256 expectedWithTakerFee = (expectedWethReceived * (feeUnit - feeTaker)) / feeUnit;
        assertApproxEqAbs(received, expectedWithTakerFee, 100, "Charlie received unexpected amount of WETH");
        assertTrue(received >= minWethReceived, "Received less than minimum required");

        console.log("\n--- Swap Results ---");
        console.log("Charlie spent: %s USDC", usdcToSwap);
        console.log("Charlie received: %s WETH", received);
        console.log("Expected (ideal): %s WETH", expectedWethReceived);
        console.log("Expected (with fees): %s WETH", expectedWithTakerFee);
    }

    function testMultiUserPoolInteraction() public {
        console.log("\n=== MULTI-USER POOL INTERACTION TEST ===");

        // Get initial balances
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);
        uint256 aliceInitialUsdcBalance = usdc.balanceOf(alice);
        uint256 bobInitialWethBalance = weth.balanceOf(bob);
        uint256 bobInitialUsdcBalance = usdc.balanceOf(bob);
        uint256 charlieInitialWethBalance = weth.balanceOf(charlie);
        uint256 charlieInitialUsdcBalance = usdc.balanceOf(charlie);
        uint256 davidInitialWethBalance = weth.balanceOf(david);
        uint256 davidInitialUsdcBalance = usdc.balanceOf(david);

        console.log("--- Initial Balances ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);

        // 1. Alice adds liquidity at 2000 USDC/ETH
        vm.startPrank(alice);
        console.log("--- Alice places sell order at 2000 USDC per WETH ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            2000e6, // 1 ETH = 2000 USDC
            5e18, // 5 ETH
            IOrderBook.Side.SELL,
            alice
        );
        vm.stopPrank();

        // 2. Bob adds liquidity at a slightly different price
        vm.startPrank(bob);
        console.log("--- Bob places sell order at 2010 USDC per WETH ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            2010e6, // 1 ETH = 2010 USDC (slightly different price)
            5e18, // 5 ETH
            IOrderBook.Side.SELL,
            bob
        );
        vm.stopPrank();

        // Check balances after liquidity provision
        console.log("\n--- Balances After Liquidity Provision ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);

        // 3. Charlie performs a swap
        vm.startPrank(charlie);
        console.log("\n--- Charlie swaps 4000 USDC for WETH ---");
        uint256 usdcToSwap = 4000e6; // 4000 USDC
        uint256 minWethReceived = 1.9e18; // 1.9 ETH (expecting ~2 ETH)

        uint256 charlieReceived = router.swap(
            Currency.wrap(address(usdc)), Currency.wrap(address(weth)), usdcToSwap, minWethReceived, 1, charlie
        );
        vm.stopPrank();

        // 4. David performs another swap
        vm.startPrank(david);
        console.log("\n--- David swaps 2 WETH for USDC ---");
        uint256 wethToSwap = 2e18; // 2 ETH
        uint256 minUsdcReceived = 3900e6; // 3900 USDC (expecting ~4000-4020)

        uint256 davidReceived = router.swap(
            Currency.wrap(address(weth)), Currency.wrap(address(usdc)), wethToSwap, minUsdcReceived, 1, david
        );
        vm.stopPrank();

        // Check final balances
        console.log("\n--- Final Balances After Swaps ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);

        // Verify Charlie's balances
        uint256 charlieFinalUsdcBalance =
            usdc.balanceOf(charlie) + balanceManager.getBalance(charlie, Currency.wrap(address(usdc)));
        uint256 charlieFinalWethBalance =
            weth.balanceOf(charlie) + balanceManager.getBalance(charlie, Currency.wrap(address(weth)));

        assertEq(
            charlieFinalUsdcBalance, charlieInitialUsdcBalance - usdcToSwap, "Charlie's USDC not deducted correctly"
        );
        assertApproxEqAbs(
            charlieFinalWethBalance,
            charlieInitialWethBalance + charlieReceived,
            100,
            "Charlie's WETH not received correctly"
        );

        // Verify David's balances
        uint256 davidFinalWethBalance =
            weth.balanceOf(david) + balanceManager.getBalance(david, Currency.wrap(address(weth)));
        uint256 davidFinalUsdcBalance =
            usdc.balanceOf(david) + balanceManager.getBalance(david, Currency.wrap(address(usdc)));

        assertEq(davidFinalWethBalance, davidInitialWethBalance - wethToSwap, "David's WETH not deducted correctly");
        assertApproxEqAbs(
            davidFinalUsdcBalance, davidInitialUsdcBalance + davidReceived, 100, "David's USDC not received correctly"
        );

        // Expected amounts calculation
        uint256 charlieExpectedWeth = (usdcToSwap * 1e18) / 2000e6; // Using Alice's price
        uint256 davidExpectedUsdc = (wethToSwap * 2000e6) / 1e18; // Using Alice's price

        console.log("\n--- Swap Results ---");
        console.log("Charlie spent: %s USDC", usdcToSwap);
        console.log("Charlie received: %s WETH", charlieReceived);
        console.log("Charlie expected (ideal): %s WETH", charlieExpectedWeth);

        console.log("David spent: %s WETH", wethToSwap);
        console.log("David received: %s USDC", davidReceived);
        console.log("David expected (ideal): %s USDC", davidExpectedUsdc);
    }

    function testComplexMultiUserSwap() public {
        console.log("\n=== COMPLEX MULTI-USER SWAP TEST ===");

        // Get initial balances for all participants
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);
        uint256 aliceInitialUsdcBalance = usdc.balanceOf(alice);
        uint256 bobInitialWethBalance = weth.balanceOf(bob);
        uint256 bobInitialUsdcBalance = usdc.balanceOf(bob);
        uint256 charlieInitialWethBalance = weth.balanceOf(charlie);
        uint256 charlieInitialUsdcBalance = usdc.balanceOf(charlie);
        uint256 davidInitialWethBalance = weth.balanceOf(david);
        uint256 davidInitialUsdcBalance = usdc.balanceOf(david);

        console.log("--- Initial Balances ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);

        // Define order parameters for multiple users at different price levels
        // For selling ETH (receiving USDC), we need to place buy orders
        uint128 alicePrice = 2505e6; // Highest price (most generous to taker)
        uint128 charliePrice = 2502e6; // Middle price
        uint128 davidPrice = 2500e6; // Lowest price

        uint128 aliceQuantity = 1e18; // 1 ETH
        uint128 charlieQuantity = 1e18; // 1 ETH
        uint128 davidQuantity = 1e18; // 1 ETH

        // Create a series of buy orders at different price levels from multiple users
        // Since Bob will be selling WETH to get USDC, these are BUY orders
        // to provide liquidity to receive WETH
        vm.startPrank(alice);
        console.log("--- Alice places BUY order at 2505 USDC per WETH (1 ETH) ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            alicePrice,
            aliceQuantity,
            IOrderBook.Side.BUY, // BUY order to receive WETH
            alice
        );
        vm.stopPrank();

        vm.startPrank(charlie);
        console.log("--- Charlie places BUY order at 2502 USDC per WETH (1 ETH) ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            charliePrice,
            charlieQuantity,
            IOrderBook.Side.BUY, // BUY order to receive WETH,
            charlie
        );
        vm.stopPrank();

        vm.startPrank(david);
        console.log("--- David places BUY order at 2500 USDC per WETH (1 ETH) ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            davidPrice,
            davidQuantity,
            IOrderBook.Side.BUY, // BUY order to receive WETH
            david
        );
        vm.stopPrank();

        // Check locked balances after order placement
        console.log("\n--- Balances After Order Placement ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);
        logBalance("David", david);

        // Calculate expected values for each maker - they're providing USDC
        uint256 aliceExpectedLocked = (uint256(alicePrice) * uint256(aliceQuantity)) / 1e18;
        uint256 charlieExpectedLocked = (uint256(charliePrice) * uint256(charlieQuantity)) / 1e18;
        uint256 davidExpectedLocked = (uint256(davidPrice) * uint256(davidQuantity)) / 1e18;

        // Verify locked USDC for each maker's buy order
        uint256 aliceLockedUsdc =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)));
        uint256 charlieLockedUsdc =
            balanceManager.getLockedBalance(charlie, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)));
        uint256 davidLockedUsdc =
            balanceManager.getLockedBalance(david, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)));

        assertApproxEqAbs(aliceLockedUsdc, aliceExpectedLocked, 100, "Alice's locked USDC incorrect");
        assertApproxEqAbs(charlieLockedUsdc, charlieExpectedLocked, 100, "Charlie's locked USDC incorrect");
        assertApproxEqAbs(davidLockedUsdc, davidExpectedLocked, 100, "David's locked USDC incorrect");

        // Bob performs a market swap to sell WETH for USDC
        // This will match against the buy orders at the best prices first (Alice, then Charlie, then David)
        uint256 wethToSwap = 2e18; // 2 ETH - enough to match multiple orders
        uint256 expectedAliceTradeValue = (uint256(alicePrice) * uint256(aliceQuantity)) / (10 ** 18);
        uint256 expectedCharlieTradeValue = (uint256(charliePrice) * uint256(charlieQuantity)) / (10 ** 18);
        uint256 totalExpectedTradeValue = expectedAliceTradeValue + expectedCharlieTradeValue;
        uint256 minUsdcReceived = (totalExpectedTradeValue * (feeUnit - feeTaker)) / feeUnit; // Minimum USDC expected (slightly less than 5000 due to fees)
        vm.startPrank(bob);

        console.log("\n--- Bob swaps 2 WETH for USDC (market order) ---");
        uint256 usdcReceived = router.swap(
            Currency.wrap(address(weth)), // Source currency (what Bob is selling)
            Currency.wrap(address(usdc)), // Destination currency (what Bob is buying)
            wethToSwap, // Amount of WETH to sell
            minUsdcReceived, // Minimum USDC to receive
            1, // Max 1 hop (direct swap)
            bob
        );
        vm.stopPrank();

        // Check final balances for all users
        console.log("\n--- Final Balances After Market Order ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);

        // Verify Bob's balances - he should have spent WETH and received USDC
        uint256 bobFinalWethBalance = weth.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(weth)));
        uint256 bobFinalUsdcBalance = usdc.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(usdc)));

        uint256 bobWethDecrease = bobInitialWethBalance - bobFinalWethBalance;
        uint256 bobUsdcIncrease = bobFinalUsdcBalance - bobInitialUsdcBalance;

        assertEq(bobWethDecrease, wethToSwap, "Bob should have spent exactly 2 WETH");

        console.log("bobUsdcIncrease", bobUsdcIncrease);
        console.log("minUsdcReceived", minUsdcReceived);

        assertTrue(bobUsdcIncrease >= minUsdcReceived, "Bob should have received at least minimum USDC");

        // Assuming orders are matched in price-time priority, better prices get matched first
        // So Alice's order should be fully matched
        uint256 aliceFinalWethBalance =
            weth.balanceOf(alice) + balanceManager.getBalance(alice, Currency.wrap(address(weth)));
        uint256 aliceWethIncrease = aliceFinalWethBalance - aliceInitialWethBalance;

        // Alice should have received some WETH
        assertTrue(aliceWethIncrease > 0, "Alice should have received WETH");

        // If Alice's order was fully matched, her locked USDC should be reduced
        uint256 aliceFinalLockedUsdc =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)));
        assertTrue(aliceFinalLockedUsdc < aliceLockedUsdc, "Alice's locked USDC should have decreased");

        console.log("\n--- Swap Results ---");
        console.log("Bob spent: %s WETH", bobWethDecrease);
        console.log("Bob received: %s USDC", bobUsdcIncrease);
        console.log("Alice WETH received: %s", aliceWethIncrease);

        // Check if other orders were matched
        uint256 charlieWethReceived = weth.balanceOf(charlie)
            + balanceManager.getBalance(charlie, Currency.wrap(address(weth))) - charlieInitialWethBalance;

        uint256 davidWethReceived = weth.balanceOf(david)
            + balanceManager.getBalance(david, Currency.wrap(address(weth))) - davidInitialWethBalance;

        if (charlieWethReceived > 0) {
            console.log("Charlie received: %s WETH", charlieWethReceived);
        }

        if (davidWethReceived > 0) {
            console.log("David received: %s WETH", davidWethReceived);
        }

        // Total WETH received by all makers should equal what Bob spent
        assertApproxEqAbs(
            aliceWethIncrease + charlieWethReceived + davidWethReceived,
            (bobWethDecrease * (feeUnit - feeMaker)) / feeUnit,
            100,
            "Total WETH received by makers should equal what Bob spent"
        );
    }

    function testTwoHopSwap() public {
        console.log("\n=== TWO-HOP SWAP TEST (WETH -> USDC -> WBTC) ===");

        // Get initial balances for participants
        uint256 aliceInitialWethBalance = weth.balanceOf(alice);
        uint256 aliceInitialWbtcBalance = wbtc.balanceOf(alice);
        uint256 aliceInitialUsdcBalance = usdc.balanceOf(alice);
        uint256 bobInitialWethBalance = weth.balanceOf(bob);
        uint256 bobInitialWbtcBalance = wbtc.balanceOf(bob);
        uint256 bobInitialUsdcBalance = usdc.balanceOf(bob);
        uint256 charlieInitialWethBalance = weth.balanceOf(charlie);
        uint256 charlieInitialWbtcBalance = wbtc.balanceOf(charlie);
        uint256 charlieInitialUsdcBalance = usdc.balanceOf(charlie);

        console.log("--- Initial Balances ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);

        // Set up liquidity in both required pools
        vm.startPrank(alice);
        // For WETH/USDC pool: Alice provides buy order for WETH at 2000 USDC/ETH
        console.log("--- Alice places buy order at 2000 USDC per WETH ---");
        router.placeOrderWithDeposit(
            pools["WETH/USDC"],
            2000e6, // 1 ETH = 2000 USDC
            5e18, // 5 ETH
            IOrderBook.Side.BUY,
            alice
        );
        vm.stopPrank();

        vm.startPrank(bob);
        // For WBTC/USDC pool: Bob provides sell order for WBTC at 30000 USDC/BTC
        console.log("--- Bob places sell order at 30000 USDC per WBTC ---");
        router.placeOrderWithDeposit(
            pools["WBTC/USDC"],
            30_000e6, // 1 BTC = 30000 USDC
            1e8, // 1 BTC
            IOrderBook.Side.SELL,
            bob
        );
        vm.stopPrank();

        // Check balances after liquidity provision
        console.log("\n--- Balances After Liquidity Provision ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);

        // Verify Alice's USDC was locked for ETH buy order
        uint256 aliceLockedUsdc =
            balanceManager.getLockedBalance(alice, poolOrderBooks["WETH/USDC"], Currency.wrap(address(usdc)));
        assertEq(aliceLockedUsdc, 10_000e6, "Alice's locked USDC incorrect"); // 5 ETH * 2000 USDC/ETH

        // Verify Bob's WBTC was locked for BTC sell order
        uint256 bobLockedWbtc =
            balanceManager.getLockedBalance(bob, poolOrderBooks["WBTC/USDC"], Currency.wrap(address(wbtc)));
        assertEq(bobLockedWbtc, 1e8, "Bob's locked WBTC incorrect"); // 1 BTC

        // Charlie performs a 2-hop swap: WETH -> USDC -> WBTC
        vm.startPrank(charlie);
        console.log("\n--- Charlie swaps 1 WETH for WBTC via USDC (2-hop swap) ---");
        uint256 wethToSwap = 1e18; // 1 ETH

        // Calculate expected outcome:
        // 1 ETH = 2000 USDC, 30000 USDC = 1 BTC, so 1 ETH ≈ 0.0667 BTC
        uint256 expectedUsdcIntermediate = 2000e6; // From 1 ETH
        uint256 expectedFinalWbtc = (expectedUsdcIntermediate * 1e8) / 30_000e6; // Convert to WBTC

        // Apply taker fee twice (once for each hop)
        uint256 expectedUsdcAfterFee = (expectedUsdcIntermediate * (feeUnit - feeTaker)) / feeUnit;
        uint256 expectedWbtcAfterFees = (expectedFinalWbtc * (feeUnit - feeTaker)) / feeUnit;

        // Set minimum amount to receive accounting for fees (with some additional slippage buffer)
        uint256 minWbtcReceived = (expectedWbtcAfterFees * 90) / 100; // 10% additional slippage buffer

        console.log("Expected USDC intermediate (before fees): %s", expectedUsdcIntermediate);
        console.log("Expected WBTC final (before fees): %s", expectedFinalWbtc);
        console.log("Expected WBTC final (after fees): %s", expectedWbtcAfterFees);
        console.log("Minimum WBTC required: %s", minWbtcReceived);

        uint256 received = router.swap(
            Currency.wrap(address(weth)),
            Currency.wrap(address(wbtc)),
            wethToSwap,
            minWbtcReceived,
            2, // max hops = 2, allowing for WETH -> USDC -> WBTC
            charlie
        );
        vm.stopPrank();

        // Check final balances
        console.log("\n--- Final Balances After 2-Hop Swap ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);

        // Verify Charlie's balances
        uint256 charlieFinalWethBalance =
            weth.balanceOf(charlie) + balanceManager.getBalance(charlie, Currency.wrap(address(weth)));
        uint256 charlieFinalWbtcBalance =
            wbtc.balanceOf(charlie) + balanceManager.getBalance(charlie, Currency.wrap(address(wbtc)));

        assertEq(
            charlieFinalWethBalance, charlieInitialWethBalance - wethToSwap, "Charlie's WETH not deducted correctly"
        );
        assertEq(charlieFinalWbtcBalance, charlieInitialWbtcBalance + received, "Charlie's WBTC not received correctly");

        // Verify Alice received some WETH (from the first hop)
        uint256 aliceFinalWethBalance =
            weth.balanceOf(alice) + balanceManager.getBalance(alice, Currency.wrap(address(weth)));
        uint256 aliceWethIncrease = aliceFinalWethBalance - aliceInitialWethBalance;

        assertTrue(aliceWethIncrease > 0, "Alice should have received WETH");

        // Verify Bob received some USDC (from the second hop)
        uint256 bobFinalUsdcBalance = usdc.balanceOf(bob) + balanceManager.getBalance(bob, Currency.wrap(address(usdc)));
        uint256 bobUsdcIncrease = bobFinalUsdcBalance - bobInitialUsdcBalance;

        assertTrue(bobUsdcIncrease > 0, "Bob should have received USDC");

        // Verify received amount is within expected range
        assertApproxEqAbs(
            received,
            expectedWbtcAfterFees,
            1e6, // Allow small difference due to rounding
            "Charlie received unexpected amount of WBTC"
        );
        assertTrue(received >= minWbtcReceived, "Received less than minimum required");

        console.log("\n--- 2-Hop Swap Results ---");
        console.log("Charlie spent: %s WETH", wethToSwap);
        console.log("Charlie received: %s WBTC", received);
        console.log("Expected (ideal): %s WBTC", expectedFinalWbtc);
        console.log("Expected (with fees): %s WBTC", expectedWbtcAfterFees);
        console.log("Alice WETH received: %s", aliceWethIncrease);
        console.log("Bob USDC received: %s", bobUsdcIncrease);
    }

    // Helper functions
    function addressToString(
        address _addr
    ) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function uint256ToString(
        uint256 _i
    ) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
