// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/token/GTXToken.sol";
import "../../src/mocks/MockToken.sol";
import "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import "../../src/incentives/voting-controller/VotingControllerUpg.sol";
import "../../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import "../../src/incentives/libraries/WeekMath.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import "../../src/marketmaker/GTXMarketMakerVault.sol";
import "../../src/marketmaker/GTXMarketMakerFactory.sol";
import "../../src/marketmaker/GTXMarketMakerFactoryStorage.sol";
import "../../src/marketmaker/GTXMarketMakerVaultStorage.sol";
import "../../src/BalanceManager.sol";
import "../../src/PoolManager.sol";
import "../../src/GTXRouter.sol";
import "../../src/OrderBook.sol";

contract GTXIncentiveSystemTest is Test {
    GTXToken public token;
    VotingEscrowMainchain public veToken;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;
    GTXMarketMakerFactory public factory;

    // GTX infrastructure
    BalanceManager public balanceManager;
    PoolManager public poolManager;
    GTXRouter public router;
    UpgradeableBeacon public orderBookBeacon;

    GTXMarketMakerVault public pool1Vault;
    GTXMarketMakerVault public pool2Vault;

    address public owner;
    address public alice;
    address public bob;
    address public WBTCUSDC;
    address public WETHUSDC;

    uint256 constant INITIAL_BALANCE = 1_000_000 * 1e18;
    uint256 constant LOCK_AMOUNT = 100_000 * 1e18;
    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;
    uint256 constant LIQUIDITY = 1_000 * 1e18;
    uint256 constant WEEKLY_EMISSION = 10_000 * 1e18;

    address[] pools;
    uint64[] chainIds;

    // Mock tokens for testing
    MockToken public wbtc;
    MockToken public weth;
    MockToken public usdc;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Set up GTX token and incentive system
        token = new GTXToken();
        veToken = new VotingEscrowMainchain(address(token), address(0), 0);

        VotingControllerUpg votingImpl = new VotingControllerUpg(
            address(veToken),
            address(0)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(votingImpl),
            address(this),
            abi.encodeWithSelector(VotingControllerUpg.initialize.selector, 0)
        );
        votingController = VotingControllerUpg(address(proxy));

        // Create mock tokens for trading pairs
        wbtc = new MockToken("Wrapped BTC", "WBTC", 8);
        
        weth = new MockToken("Wrapped ETH", "WETH", 18);
        
        usdc = new MockToken("USD Coin", "USDC", 6);
        
        // Mint tokens to this contract
        wbtc.mint(address(this), 1000 * 10**8);  // 1000 WBTC
        weth.mint(address(this), 1000 * 10**18); // 1000 WETH
        usdc.mint(address(this), 10000000 * 10**6); // 10M USDC
        
        // Mint tokens to users
        wbtc.mint(alice, 100 * 10**8);
        weth.mint(alice, 100 * 10**18);
        usdc.mint(alice, 1000000 * 10**6);
        
        wbtc.mint(bob, 100 * 10**8);
        weth.mint(bob, 100 * 10**18);
        usdc.mint(bob, 1000000 * 10**6);

        // Set up GTX infrastructure
        
        // 1. Balance Manager
        balanceManager = new BalanceManager();
        balanceManager.initialize(address(this), address(this), 20, 30); // 0.2% maker fee, 0.3% taker fee
        
        // 2. OrderBook Beacon
        OrderBook orderBookImpl = new OrderBook();
        orderBookBeacon = new UpgradeableBeacon(address(orderBookImpl), address(this));
        
        // 3. Pool Manager
        poolManager = new PoolManager();
        poolManager.initialize(address(this), address(balanceManager), address(orderBookBeacon));
        
        // 4. Router
        router = new GTXRouter();
        router.initialize(address(this), address(poolManager));
        
        // Set router in pool manager
        poolManager.setRouter(address(router));
        
        // Create and initialize vault implementation
        GTXMarketMakerVault vaultImplementation = new GTXMarketMakerVault();
        
        // Set up market maker factory
        factory = new GTXMarketMakerFactory();
        factory.initialize(
            address(this),
            address(veToken),
            address(0), // Will set later
            address(router),
            address(poolManager),
            address(balanceManager),
            address(vaultImplementation)
        );

        // Set up gauge controller
        GaugeControllerMainchainUpg gaugeImpl = new GaugeControllerMainchainUpg(
            address(votingController),
            address(token),
            address(factory)
        );
        
        TransparentUpgradeableProxy gaugeProxy = new TransparentUpgradeableProxy(
            address(gaugeImpl),
            address(this),
            abi.encodeWithSelector(GaugeControllerMainchainUpg.initialize.selector)
        );
        gaugeController = GaugeControllerMainchainUpg(address(gaugeProxy));

        // Update factory with gauge controller address
        factory.updateGaugeAddresses(address(veToken), address(gaugeController));
        
        // Set parameter constraints
        factory.updateParameterConstraints(
            1000,   // minTargetRatio (10%)
            9000,   // maxTargetRatio (90%)
            5,      // minSpread (0.05%)
            500,    // maxSpread (5%)
            0.01 * 10**8, // minOrderSize - WBTC decimals
            100 * 10**8,  // maxOrderSize - WBTC decimals
            10,     // minSlippageTolerance (0.1%)
            200,    // maxSlippageTolerance (2%)
            2,      // minActiveOrders
            100,    // maxActiveOrders
            5 minutes, // minRebalanceInterval
            7 days     // maxRebalanceInterval
        );

        // Create market maker vaults with recommended parameters
        WBTCUSDC = factory.createVaultWithRecommendedParams(
            "WBTC-USDC LP", 
            "LP1", 
            address(wbtc), 
            address(usdc)
        );
        pool1Vault = GTXMarketMakerVault(WBTCUSDC);
        
        WETHUSDC = factory.createVaultWithRecommendedParams(
            "WETH-USDC LP", 
            "LP2",
            address(weth),
            address(usdc)
        );
        pool2Vault = GTXMarketMakerVault(WETHUSDC);

        pools.push(WBTCUSDC);
        pools.push(WETHUSDC);

        chainIds.push(uint64(block.chainid));
        chainIds.push(uint64(block.chainid));

        votingController.addDestinationContract(
            address(gaugeController),
            block.chainid
        );
        votingController.addMultiPools(chainIds, pools);

        token.transfer(alice, INITIAL_BALANCE);
        token.transfer(bob, INITIAL_BALANCE);

        _lock(alice);
        _lock(bob);
    }

    function _lock(address user) internal {
        vm.startPrank(user);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 lockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);
        vm.stopPrank();
    }

    function _fundEmission(uint256 amount) internal {
        token.mint(address(this), amount);
        token.approve(address(gaugeController), amount);
        gaugeController.fundToken(amount);
    }

    function test_rewardDistribution_oneEpoch() public {
        // Approve tokens for deposit
        vm.startPrank(alice);
        wbtc.approve(address(pool1Vault), 10 * 10**8);
        usdc.approve(address(pool1Vault), 200000 * 10**6);
        weth.approve(address(pool2Vault), 10 * 10**18);
        usdc.approve(address(pool2Vault), 200000 * 10**6);
        
        // Deposit liquidity (using both base and quote)
        pool1Vault.deposit(1 * 10**8, 20000 * 10**6);
        pool2Vault.deposit(1 * 10**18, 20000 * 10**6);
        vm.stopPrank();

        vm.startPrank(bob);
        wbtc.approve(address(pool1Vault), 10 * 10**8);
        usdc.approve(address(pool1Vault), 200000 * 10**6);
        weth.approve(address(pool2Vault), 10 * 10**18);
        usdc.approve(address(pool2Vault), 200000 * 10**6);
        
        pool1Vault.deposit(1 * 10**8, 20000 * 10**6);
        pool2Vault.deposit(1 * 10**18, 20000 * 10**6);
        vm.stopPrank();

        // Vote after deposits
        vm.startPrank(alice);
        votingController.vote(pools, _u64(5e17, 5e17));
        vm.stopPrank();

        vm.startPrank(bob);
        votingController.vote(pools, _u64(5e17, 5e17));
        vm.stopPrank();

        // Set token rewards and fund the gauge controller
        uint256 tokenPerSec = 1e16;
        uint256 fundAmount = tokenPerSec * WEEK;
        token.mint(address(this), fundAmount);
        token.approve(address(gaugeController), fundAmount);
        gaugeController.fundToken(fundAmount);
        votingController.setTokenPerSec(uint128(tokenPerSec));

        // Advance time by a week to allow epoch finalization
        vm.warp(block.timestamp + WEEK);
        vm.roll(block.number + 50400);

        // Finalize and broadcast results
        votingController.finalizeEpoch();
        votingController.broadcastResults(uint64(block.chainid));

        vm.warp(block.timestamp + 10 hours);
        vm.roll(block.number + 3000);

        // Store initial balances and state
        uint256 aliceInitialBalance = token.balanceOf(alice);
        uint256 bobInitialBalance = token.balanceOf(bob);

        // Users claim rewards - this will trigger internal market maker reward claims
        vm.startPrank(alice);
        pool1Vault.redeemRewards();
        pool2Vault.redeemRewards();
        vm.stopPrank();

        // Advance blocks to allow rewards to accumulate
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 300);

        vm.startPrank(bob);
        pool1Vault.redeemRewards();
        pool2Vault.redeemRewards();
        vm.stopPrank();

        // Log final state
        uint256 aliceFinalBalance = token.balanceOf(alice);
        uint256 bobFinalBalance = token.balanceOf(bob);

        console.log("\nFinal state:");
        console.log("Alice rewards:", aliceFinalBalance - aliceInitialBalance);
        console.log("Bob rewards:", bobFinalBalance - bobInitialBalance);

        // Verify rewards were received
        assertGt(
            token.balanceOf(alice),
            aliceInitialBalance,
            "Alice should receive rewards"
        );
        assertGt(
            token.balanceOf(bob),
            bobInitialBalance,
            "Bob should receive rewards"
        );
    }

    function test_rewardDistribution_multipleEpochs() public {
        // Approve tokens for deposit
        vm.startPrank(alice);
        wbtc.approve(address(pool1Vault), 10 * 10**8);
        usdc.approve(address(pool1Vault), 200000 * 10**6);
        weth.approve(address(pool2Vault), 10 * 10**18);
        usdc.approve(address(pool2Vault), 200000 * 10**6);
        
        // Deposit liquidity (using both base and quote)
        pool1Vault.deposit(1 * 10**8, 20000 * 10**6);
        pool2Vault.deposit(1 * 10**18, 20000 * 10**6);
        vm.stopPrank();

        vm.startPrank(bob);
        wbtc.approve(address(pool1Vault), 10 * 10**8);
        usdc.approve(address(pool1Vault), 200000 * 10**6);
        weth.approve(address(pool2Vault), 10 * 10**18);
        usdc.approve(address(pool2Vault), 200000 * 10**6);
        
        pool1Vault.deposit(1 * 10**8, 20000 * 10**6);
        pool2Vault.deposit(1 * 10**18, 20000 * 10**6);
        vm.stopPrank();

        // Set token rewards and fund the gauge controller
        uint256 tokenPerSec = 1e16;
        uint256 fundAmount = tokenPerSec * WEEK * 3; // Fund for 3 epochs
        token.mint(address(this), fundAmount);
        token.approve(address(gaugeController), fundAmount);
        gaugeController.fundToken(fundAmount);
        votingController.setTokenPerSec(uint128(tokenPerSec));

        // Track balances across epochs
        uint256[] memory aliceBalances = new uint256[](4); // Initial + 3 epochs
        uint256[] memory bobBalances = new uint256[](4);

        // Record initial balances
        aliceBalances[0] = token.balanceOf(alice);
        bobBalances[0] = token.balanceOf(bob);

        // Test across 3 epochs
        for (uint256 epoch = 1; epoch <= 3; epoch++) {
            // Vote for the current epoch
            vm.startPrank(alice);
            votingController.vote(pools, _u64(5e17, 5e17));
            vm.stopPrank();

            vm.startPrank(bob);
            votingController.vote(pools, _u64(5e17, 5e17));
            vm.stopPrank();

            // Advance time to end of epoch
            vm.warp(block.timestamp + WEEK);
            vm.roll(block.number + 50400);

            // Finalize and broadcast results
            votingController.finalizeEpoch();
            votingController.broadcastResults(uint64(block.chainid));

            // Advance time a bit
            vm.warp(block.timestamp + 10 hours);
            vm.roll(block.number + 3000);

            // Users claim rewards
            vm.startPrank(alice);
            pool1Vault.redeemRewards();
            pool2Vault.redeemRewards();
            vm.stopPrank();

            // Advance blocks
            vm.warp(block.timestamp + 1 hours);
            vm.roll(block.number + 300);

            vm.startPrank(bob);
            pool1Vault.redeemRewards();
            pool2Vault.redeemRewards();
            vm.stopPrank();

            // Record balances after this epoch
            aliceBalances[epoch] = token.balanceOf(alice);
            bobBalances[epoch] = token.balanceOf(bob);

            // Log rewards received in this epoch
            console.log("\nEpoch results:");
            console.log(
                "Alice rewards in epoch:",
                aliceBalances[epoch] - aliceBalances[epoch - 1]
            );
            console.log(
                "Bob rewards in epoch:",
                bobBalances[epoch] - bobBalances[epoch - 1]
            );

            // Verify rewards were received in this epoch
            assertGt(
                aliceBalances[epoch],
                aliceBalances[epoch - 1],
                "Alice should receive rewards in this epoch"
            );
            assertGt(
                bobBalances[epoch],
                bobBalances[epoch - 1],
                "Bob should receive rewards in this epoch"
            );
        }

        // Log final state
        console.log("\nOverall rewards summary:");
        console.log(
            "Alice total rewards:",
            aliceBalances[3] - aliceBalances[0]
        );
        console.log("Bob total rewards:", bobBalances[3] - bobBalances[0]);

        // This checks that reward distribution continues to work properly over time
        for (uint256 epoch = 2; epoch <= 3; epoch++) {
            uint256 alicePrevEpochRewards = aliceBalances[epoch - 1] -
                aliceBalances[epoch - 2];
            uint256 aliceCurrentEpochRewards = aliceBalances[epoch] -
                aliceBalances[epoch - 1];

            uint256 bobPrevEpochRewards = bobBalances[epoch - 1] -
                bobBalances[epoch - 2];
            uint256 bobCurrentEpochRewards = bobBalances[epoch] -
                bobBalances[epoch - 1];

            // Assert rewards don't decrease significantly (allow for small variances)
            assertGe(
                aliceCurrentEpochRewards,
                (alicePrevEpochRewards * 95) / 100, // Allow 5% variance
                "Alice rewards should not decrease significantly between epochs"
            );

            assertGe(
                bobCurrentEpochRewards,
                (bobPrevEpochRewards * 95) / 100, // Allow 5% variance
                "Bob rewards should not decrease significantly between epochs"
            );
        }
    }

    function _u64(
        uint64 a,
        uint64 b
    ) internal pure returns (uint64[] memory r) {
        r = new uint64[](2);
        r[0] = a;
        r[1] = b;
    }
}