pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../src/token/GTXToken.sol";
import "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import "../../src/incentives/voting-controller/VotingControllerUpg.sol";
import "../../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import "../../src/incentives/libraries/WeekMath.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/token/GTXDistributor.sol";
import "../../src/marketmaker/MarketMaker.sol";
import "../../src/marketmaker/MarketMakerFactory.sol";

contract GTXIncentiveSystemTest is Test {
    GTXToken public token;
    VotingEscrowMainchain public veToken;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;
    GTXDistributor public distributor;
    MarketMakerFactory public factory;
    MarketMaker public pool1MM;
    MarketMaker public pool2MM;

    address public owner;
    address public alice;
    address public bob;
    address public WBTCUSDC;
    address public WETHUSDC;

    uint256 constant INITIAL_BALANCE = 1000000 * 1e18;
    uint256 constant LOCK_AMOUNT = 100000 * 1e18;
    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;
    uint256 constant LIQUIDITY_AMOUNT = 1000 * 1e18;

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        WBTCUSDC = makeAddr("WBTCUSDC");
        WETHUSDC = makeAddr("WETHUSDC");

        token = new GTXToken();

        veToken = new VotingEscrowMainchain(
            address(token),
            address(0),
            0
        );

        VotingControllerUpg votingControllerImpl = new VotingControllerUpg(
            address(veToken),
            address(0)
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(votingControllerImpl),
            address(this),
            abi.encodeWithSelector(
                VotingControllerUpg.initialize.selector,
                0
            )
        );
        votingController = VotingControllerUpg(address(proxy));

        factory = new MarketMakerFactory(
            address(veToken),
            address(0)
        );

        gaugeController = new GaugeControllerMainchainUpg(
            address(votingController),
            address(token),
            address(factory)
        );

        factory.setGaugeController(address(gaugeController));

        distributor = new GTXDistributor(address(token));

        token.transferOwnership(address(distributor));

        pool1MM = MarketMaker(factory.createMarketMaker("WBTCUSDC LP", "LP1"));
        pool2MM = MarketMaker(factory.createMarketMaker("WETHUSDC LP", "LP2"));
        WBTCUSDC = address(pool1MM);
        WETHUSDC = address(pool2MM);

        distributor.setRewardDistributor(address(gaugeController), true);

        token.transfer(alice, INITIAL_BALANCE);
        token.transfer(bob, INITIAL_BALANCE);

        address[] memory pools = new address[](2);
        pools[0] = WBTCUSDC;
        pools[1] = WETHUSDC;
        uint64[] memory chainIds = new uint64[](2);
        chainIds[0] = uint64(block.chainid);
        chainIds[1] = uint64(block.chainid);

        votingController.addMultiPools(chainIds, pools);
    }

    function test_lockAndVotingPower() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 lockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);
        vm.stopPrank();

        (uint128 amount, uint128 expiry) = veToken.positionData(alice);
        assertEq(amount, LOCK_AMOUNT);
        assertGt(expiry, block.timestamp + YEAR - 1 weeks);

        uint128 votingPower = veToken.balanceOf(alice);
        assertGt(votingPower, 0);
    }

    function test_votingMechanism() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);

        uint128 lockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);

        address[] memory pools = new address[](2);
        pools[0] = WBTCUSDC;
        pools[1] = WETHUSDC;

        uint64[] memory weights = new uint64[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        votingController.vote(pools, weights);
        vm.stopPrank();

        uint256 totalVotingPower = veToken.balanceOf(alice);
        assertTrue(totalVotingPower > 0);
    }

    function test_epochFinalization() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 lockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);

        address[] memory pools = new address[](2);
        pools[0] = WBTCUSDC;
        pools[1] = WETHUSDC;

        uint64[] memory weights = new uint64[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        votingController.vote(pools, weights);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 bobLockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), bobLockEnd);

        weights[0] = 3000;
        weights[1] = 7000;

        votingController.vote(pools, weights);
        vm.stopPrank();

        vm.warp(block.timestamp + WEEK);

        votingController.finalizeEpoch();

        uint128 lastWeek = WeekMath.getCurrentWeekStart();
        address[] memory poolAddresses = new address[](2);
        poolAddresses[0] = WBTCUSDC;
        poolAddresses[1] = WETHUSDC;
        (
            bool isEpochFinalized,
            uint256 totalVotes,
            uint128[] memory poolVotes
        ) = votingController.getWeekData(lastWeek, poolAddresses);
        assertTrue(isEpochFinalized);
    }

    function test_lockExtensionAndVoting() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 initialLockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + 90 days)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), initialLockEnd);

        uint128 initialVotingPower = veToken.balanceOf(alice);

        uint128 newLockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(0, newLockEnd);

        uint128 newVotingPower = veToken.balanceOf(alice);
        vm.stopPrank();

        assertGt(newVotingPower, initialVotingPower);
    }

    function test_failVoteWithoutLock() public {
        address[] memory pools = new address[](1);
        pools[0] = WBTCUSDC;

        uint64[] memory weights = new uint64[](1);
        weights[0] = 10000;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSignature("VCZeroVeToken(address)", alice)
        );
        votingController.vote(pools, weights);
    }

    function test_failExceedMaxWeight() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);
        veToken.increaseLockPosition(
            uint128(LOCK_AMOUNT),
            uint128(block.timestamp + YEAR)
        );

        address[] memory pools = new address[](2);
        pools[0] = WBTCUSDC;
        pools[1] = WETHUSDC;

        uint64[] memory weights = new uint64[](2);
        weights[0] = 6000;
        weights[1] = 5000;

        vm.expectRevert(
            abi.encodeWithSignature(
                "VCExceededMaxWeight(uint256,uint256)",
                11000,
                1e18
            )
        );
        votingController.vote(pools, weights);
        vm.stopPrank();
    }

    function test_rewardDistribution() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 lockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);

        address[] memory pools = new address[](2);
        pools[0] = WBTCUSDC;
        pools[1] = WETHUSDC;

        uint64[] memory weights = new uint64[](2);
        weights[0] = 7000;
        weights[1] = 3000;
        votingController.vote(pools, weights);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(veToken), LOCK_AMOUNT);
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);

        weights[0] = 3000;
        weights[1] = 7000;
        votingController.vote(pools, weights);
        vm.stopPrank();

        vm.startPrank(alice);
        pool1MM.deposit(LIQUIDITY_AMOUNT);
        pool2MM.deposit(LIQUIDITY_AMOUNT / 5);
        vm.stopPrank();

        vm.startPrank(bob);
        pool1MM.deposit(LIQUIDITY_AMOUNT / 5);
        pool2MM.deposit(LIQUIDITY_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + WEEK);

        votingController.finalizeEpoch();
        distributor.advanceEpoch();

        uint256 epochId = distributor.getCurrentEpoch() - 1;
        GTXDistributor.EpochInfo memory epochInfo = distributor.getEpochInfo(
            epochId
        );
        uint256 tokensToDistribute = epochInfo.tokensToDistribute;

        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        uint256[] memory rewards = new uint256[](2);
        rewards[0] = (tokensToDistribute * 45) / 100;
        rewards[1] = (tokensToDistribute * 55) / 100;

        vm.prank(address(gaugeController));
        distributor.distributeRewards(epochId, users, rewards);

        vm.prank(alice);
        distributor.claimRewards(epochId);
        vm.prank(bob);
        distributor.claimRewards(epochId);

        uint256 aliceBalance = token.balanceOf(alice);
        uint256 bobBalance = token.balanceOf(bob);

        assertGt(aliceBalance, INITIAL_BALANCE - LOCK_AMOUNT);
        assertGt(bobBalance, INITIAL_BALANCE - LOCK_AMOUNT);
        assertGt(
            bobBalance - (INITIAL_BALANCE - LOCK_AMOUNT),
            aliceBalance - (INITIAL_BALANCE - LOCK_AMOUNT)
        );
    }

    function test_multiEpochRewardDistribution() public {
        vm.startPrank(alice);
        token.approve(address(veToken), LOCK_AMOUNT);
        uint128 lockEnd = uint128(
            WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) +
                WEEK
        );
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(veToken), LOCK_AMOUNT);
        veToken.increaseLockPosition(uint128(LOCK_AMOUNT), lockEnd);
        vm.stopPrank();

        vm.startPrank(alice);
        address[] memory pools = new address[](2);
        pools[0] = WBTCUSDC;
        pools[1] = WETHUSDC;

        uint64[] memory weights = new uint64[](2);
        weights[0] = 8000;
        weights[1] = 2000;
        votingController.vote(pools, weights);

        pool1MM.deposit(LIQUIDITY_AMOUNT);
        pool2MM.deposit(LIQUIDITY_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        weights[0] = 4000;
        weights[1] = 6000;
        votingController.vote(pools, weights);

        pool1MM.deposit(LIQUIDITY_AMOUNT / 2);
        pool2MM.deposit(LIQUIDITY_AMOUNT * 2);
        vm.stopPrank();

        vm.warp(block.timestamp + WEEK);
        votingController.finalizeEpoch();
        distributor.advanceEpoch();

        uint256 epoch1Id = distributor.getCurrentEpoch() - 1;
        GTXDistributor.EpochInfo memory epoch1Info = distributor.getEpochInfo(
            epoch1Id
        );

        address[] memory users = new address[](2);
        users[0] = alice;
        users[1] = bob;

        uint256[] memory epoch1Rewards = new uint256[](2);
        epoch1Rewards[0] = (epoch1Info.tokensToDistribute * 40) / 100;
        epoch1Rewards[1] = (epoch1Info.tokensToDistribute * 60) / 100;

        vm.prank(address(gaugeController));
        distributor.distributeRewards(epoch1Id, users, epoch1Rewards);

        vm.prank(alice);
        distributor.claimRewards(epoch1Id);
        vm.prank(bob);
        distributor.claimRewards(epoch1Id);

        uint256 aliceEpoch1Balance = token.balanceOf(alice);
        uint256 bobEpoch1Balance = token.balanceOf(bob);

        vm.startPrank(alice);
        weights[0] = 3000;
        weights[1] = 7000;
        votingController.vote(pools, weights);

        pool2MM.deposit(LIQUIDITY_AMOUNT * 2);
        vm.stopPrank();

        vm.startPrank(bob);
        weights[0] = 9000;
        weights[1] = 1000;
        votingController.vote(pools, weights);

        pool2MM.withdraw(LIQUIDITY_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + (WEEK * 2));
        votingController.finalizeEpoch();
        distributor.advanceEpoch();

        uint256 epoch2Id = distributor.getCurrentEpoch() - 1;
        GTXDistributor.EpochInfo memory epoch2Info = distributor.getEpochInfo(
            epoch2Id
        );

        uint256[] memory epoch2Rewards = new uint256[](2);
        epoch2Rewards[0] = (epoch2Info.tokensToDistribute * 65) / 100;
        epoch2Rewards[1] = (epoch2Info.tokensToDistribute * 35) / 100;

        vm.prank(address(gaugeController));
        distributor.distributeRewards(epoch2Id, users, epoch2Rewards);

        vm.prank(alice);
        distributor.claimRewards(epoch2Id);
        vm.prank(bob);
        distributor.claimRewards(epoch2Id);

        uint256 aliceFinalBalance = token.balanceOf(alice);
        uint256 bobFinalBalance = token.balanceOf(bob);

        assertGt(
            bobEpoch1Balance - INITIAL_BALANCE,
            aliceEpoch1Balance - INITIAL_BALANCE,
            "Bob should have more rewards in epoch 1 due to higher total liquidity"
        );

        uint256 aliceEpoch2Rewards = aliceFinalBalance - aliceEpoch1Balance;
        uint256 bobEpoch2Rewards = bobFinalBalance - bobEpoch1Balance;
        assertGt(
            aliceEpoch2Rewards,
            bobEpoch2Rewards,
            "Alice should have more rewards in epoch 2 due to aligned voting and liquidity"
        );

        assertGt(
            aliceFinalBalance - INITIAL_BALANCE,
            0,
            "Alice should have earned rewards"
        );
        assertGt(
            bobFinalBalance - INITIAL_BALANCE,
            0,
            "Bob should have earned rewards"
        );
    }
}