// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {MockToken} from "../../src/mocks/MockToken.sol";
import {VotingEscrowMainchain} from "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingControllerUpg} from "../../src/incentives/voting-controller/VotingControllerUpg.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GaugeControllerMainchainUpg} from "../../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import {VeBalance} from "../../src/incentives/libraries/VeBalanceLib.sol";

contract VotingControllerTest is Test {
    uint256 private constant WEEK = 1 weeks;

    MockToken public token;
    VotingEscrowMainchain public votingEscrow;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;

    address public marketMaker1 = makeAddr("marketMaker1");
    address public marketMaker2 = makeAddr("marketMaker2");
    address public marketMaker3 = makeAddr("marketMaker3");

    function setUp() public {
        // mock token
        token = new MockToken("Test Token", "TEST", 18);
        token.mint(address(this), 1000e18);

        // voting escrow
        votingEscrow = new VotingEscrowMainchain(
            address(token),
            address(0),
            1e6
        );

        // voting controller
        address votingControllerImp = address(
            new VotingControllerUpg(address(votingEscrow), address(0))
        );
        votingController = VotingControllerUpg(
            address(
                new TransparentUpgradeableProxy(
                    votingControllerImp,
                    address(this),
                    abi.encodeWithSelector(
                        VotingControllerUpg.initialize.selector,
                        100_000
                    )
                )
            )
        );

        // gauge controller
        address gaugeControllerImp = address(
            new GaugeControllerMainchainUpg(
                address(votingController),
                address(token),
                address(0)
            )
        );
        gaugeController = GaugeControllerMainchainUpg(
            address(
                new TransparentUpgradeableProxy(
                    gaugeControllerImp,
                    address(this),
                    abi.encodeWithSelector(
                        GaugeControllerMainchainUpg.initialize.selector
                    )
                )
            )
        );

        // add to destination contracts
        votingController.addDestinationContract(
            address(gaugeController),
            block.chainid
        );

        // add market maker
        votingController.addPool(uint64(block.chainid), marketMaker1);
        votingController.addPool(uint64(block.chainid), marketMaker2);
        votingController.addPool(uint64(block.chainid), marketMaker3);

        // lock token
        token.mint(address(this), 100e18);
        token.approve(address(votingEscrow), 100e18);
        uint256 timeInWeeks = (block.timestamp / WEEK) * WEEK;
        votingEscrow.increaseLockPosition(
            100e18,
            uint128(timeInWeeks + 50 * WEEK)
        );
    }

    function test_vote() public {
        address[] memory pools = new address[](1);
        pools[0] = address(marketMaker1);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 1e18;
        votingController.vote(pools, weights);

        // Verify vote results
        address[] memory poolsToQuery = new address[](1);
        poolsToQuery[0] = address(marketMaker1);
        (
            uint64 votedWeight,
            VotingControllerUpg.UserPoolData[] memory voteForPools
        ) = votingController.getUserData(address(this), poolsToQuery);
        assertEq(votedWeight, 1e18, "Total voted weight should match");
        assertTrue(voteForPools[0].vote.slope > 0, "Slope should be positive");
        assertTrue(voteForPools[0].vote.bias > 0, "Bias should be positive");

        // Verify pool vote data
        uint128[] memory wTimes = new uint128[](1);
        wTimes[0] = uint128((block.timestamp / WEEK) * WEEK);
        (
            uint64 chainId,
            uint128 lastSlopeChangeAppliedAt,
            VeBalance memory totalVote,
            uint128[] memory slopeChanges
        ) = votingController.getPoolData(address(marketMaker1), wTimes);
        assertEq(
            totalVote.slope,
            voteForPools[0].vote.slope,
            "Pool slope should match user slope"
        );
        assertEq(
            totalVote.bias,
            voteForPools[0].vote.bias,
            "Pool bias should match user bias"
        );
    }

    function test_finalize_broadcast() public {
        address[] memory pools = new address[](3);
        pools[0] = address(marketMaker1);
        pools[1] = address(marketMaker2);
        pools[2] = address(marketMaker3);

        uint64[] memory weights = new uint64[](3);
        weights[0] = 166666666666666667;
        weights[1] = 333333333333333333; 
        weights[2] = 500000000000000000; 

        votingController.vote(pools, weights);

        vm.warp(block.timestamp + 1 + WEEK); 
        votingController.finalizeEpoch(); 

        uint64 chain = uint64(block.chainid);
        uint256 fee = votingController.getBroadcastResultFee(chain); // ↩︎ IPVotingController
        votingController.broadcastResults{value: fee}(chain);

        uint128 wTime = uint128(block.timestamp / WEEK * WEEK); // epoch key
        uint256 mm1Vote = votingController.getPoolTotalVoteAt(address(marketMaker1), wTime);
        uint256 mm2Vote = votingController.getPoolTotalVoteAt(address(marketMaker2), wTime);
        uint256 mm3Vote = votingController.getPoolTotalVoteAt(address(marketMaker3), wTime);

        // Check relative ratios (2:1 and 3:1)
        assertEq(mm2Vote / mm1Vote, 2, "MM2:MM1 ratio incorrect");
        assertEq(mm3Vote / mm1Vote, 3, "MM3:MM1 ratio incorrect");

        (uint128 pps1, , , ) = gaugeController.rewardData(
            address(marketMaker1)
        );
        (uint128 pps2, , , ) = gaugeController.rewardData(
            address(marketMaker2)
        );
        (uint128 pps3, , , ) = gaugeController.rewardData(
            address(marketMaker3)
        );

        assertEq(pps1 * 2, pps2, "MM2 emission ratio wrong");
        assertEq(pps1 * 3, pps3, "MM3 emission ratio wrong");
    }
}
