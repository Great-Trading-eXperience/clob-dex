// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {MockToken} from "../../src/mocks/MockToken.sol";
import {VotingEscrowMainchain} from "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingControllerUpg} from "../../src/incentives/voting-controller/VotingControllerUpg.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GaugeControllerMainchainUpg} from
    "../../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";

contract VotingControllerTest is Test {
    uint256 private constant WEEK = 1 weeks;

    MockToken public token;
    VotingEscrowMainchain public votingEscrow;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;

    address public marketMaker1 = makeAddr("marketMaker1");

    function setUp() public {
        // mock token
        token = new MockToken("Test Token", "TEST", 18);
        token.mint(address(this), 1000e18);

        // voting escrow
        votingEscrow = new VotingEscrowMainchain(address(token), address(0), 1e6);

        // voting controller
        address votingControllerImp =
            address(new VotingControllerUpg(address(votingEscrow), address(0)));
        votingController = VotingControllerUpg(
            address(
                new TransparentUpgradeableProxy(
                    votingControllerImp,
                    address(this),
                    abi.encodeWithSelector(VotingControllerUpg.initialize.selector, 100_000)
                )
            )
        );

        // gauge controller
        address gaugeControllerImp = address(
            new GaugeControllerMainchainUpg(address(votingController), address(token), address(0))
        );
        gaugeController = GaugeControllerMainchainUpg(
            address(
                new TransparentUpgradeableProxy(
                    gaugeControllerImp,
                    address(this),
                    abi.encodeWithSelector(GaugeControllerMainchainUpg.initialize.selector)
                )
            )
        );

        // add to destination contracts
        votingController.addDestinationContract(address(gaugeController), block.chainid);

        // add market maker
        votingController.addPool(uint64(block.chainid), marketMaker1);

        // lock token
        token.mint(address(this), 100e18);
        token.approve(address(votingEscrow), 100e18);
        uint256 timeInWeeks = (block.timestamp / WEEK) * WEEK;
        votingEscrow.increaseLockPosition(100e18, uint128(timeInWeeks + 50 * WEEK));
    }

    function test_vote() public {
        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(marketMaker1);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 1e18;
        votingController.vote(pools, weights);
    }

    function test_finalize_broadcast() public {
        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(marketMaker1);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 1e18;
        votingController.vote(pools, weights);

        vm.warp(block.timestamp + 1 + WEEK);

        votingController.finalizeEpoch();

        votingController.broadcastResults(uint64(block.chainid));
    }
}
