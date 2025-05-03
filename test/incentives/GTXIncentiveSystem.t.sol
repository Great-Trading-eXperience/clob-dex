// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../../src/token/GTXToken.sol";
import "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import "../../src/incentives/voting-controller/VotingControllerUpg.sol";
import "../../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import "../../src/incentives/libraries/WeekMath.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../src/marketmaker/MarketMaker.sol";
import "../../src/marketmaker/MarketMakerFactory.sol";

contract GTXIncentiveSystemTest is Test {
    GTXToken public token;
    VotingEscrowMainchain public veToken;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;
    MarketMakerFactory public factory;

    MarketMaker public pool1MM;
    MarketMaker public pool2MM;

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

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

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

        factory = new MarketMakerFactory(address(veToken), address(0));

        gaugeController = new GaugeControllerMainchainUpg(
            address(votingController),
            address(token),
            address(factory)
        );
        factory.setGaugeController(address(gaugeController));

        pool1MM = MarketMaker(factory.createMarketMaker("WBTCUSDC LP", "LP1"));
        pool2MM = MarketMaker(factory.createMarketMaker("WETHUSDC LP", "LP2"));

        WBTCUSDC = address(pool1MM);
        WETHUSDC = address(pool2MM);

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
        vm.startPrank(alice);
        pool1MM.deposit(LIQUIDITY);
        pool2MM.deposit(LIQUIDITY);
        vm.stopPrank();

        vm.startPrank(bob);
        pool1MM.deposit(LIQUIDITY);
        pool2MM.deposit(LIQUIDITY);
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
        pool1MM.redeemRewards();
        pool2MM.redeemRewards();
        vm.stopPrank();

        // Advance blocks to allow rewards to accumulate
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + 300);

        vm.startPrank(bob);
        pool1MM.redeemRewards();
        pool2MM.redeemRewards();
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
        // Initial deposits from both users
        vm.startPrank(alice);
        pool1MM.deposit(LIQUIDITY);
        pool2MM.deposit(LIQUIDITY);
        vm.stopPrank();

        vm.startPrank(bob);
        pool1MM.deposit(LIQUIDITY);
        pool2MM.deposit(LIQUIDITY);
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
            pool1MM.redeemRewards();
            pool2MM.redeemRewards();
            vm.stopPrank();

            // Advance blocks
            vm.warp(block.timestamp + 1 hours);
            vm.roll(block.number + 300);

            vm.startPrank(bob);
            pool1MM.redeemRewards();
            pool2MM.redeemRewards();
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
