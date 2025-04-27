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
import {MarketMakerFactory} from "../../src/marketmaker/MarketMakerFactory.sol";
import {MarketMaker} from "../../src/marketmaker/MarketMaker.sol";

contract GaugeTest is Test {
    uint256 private constant WEEK = 1 weeks;

    MockToken public token;
    VotingEscrowMainchain public votingEscrow;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;
    MarketMakerFactory public marketMakerFactory;
    MarketMaker public marketMaker;

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

        // market maker factory
        marketMakerFactory = new MarketMakerFactory(address(votingEscrow), address(gaugeController));

        // gauge controller
        address gaugeControllerImp = address(
            new GaugeControllerMainchainUpg(
                address(votingController), address(token), address(marketMakerFactory)
            )
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

        // fund gauge controller
        token.mint(address(gaugeController), 1000e18);
        token.approve(address(gaugeController), 1000e18);
        gaugeController.fundToken(1000e18);

        // set token per second
        votingController.setTokenPerSec(1);

        marketMakerFactory.setVeToken(address(votingEscrow));
        marketMakerFactory.setGaugeController(address(gaugeController));
        address mm = marketMakerFactory.createMarketMaker("name", "symbol");
        marketMaker = MarketMaker(mm);

        // deposit to market maker
        marketMaker.deposit(100e18);

        // add to destination contracts
        votingController.addDestinationContract(address(gaugeController), block.chainid);

        // add market maker
        votingController.addPool(uint64(block.chainid), address(marketMaker));

        // lock token
        token.mint(address(this), 100e18);
        token.approve(address(votingEscrow), 100e18);
        uint256 timeInWeeks = (block.timestamp / WEEK) * WEEK;
        votingEscrow.increaseLockPosition(100e18, uint128(timeInWeeks + 50 * WEEK));

        // vote
        address[] memory pools = new address[](1);
        pools[0] = address(marketMaker);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 1e18;
        votingController.vote(pools, weights);

        vm.warp(block.timestamp + 1 days + WEEK);

        votingController.finalizeEpoch();
        votingController.broadcastResults(uint64(block.chainid));
    }

    function test_redeemRewards() public {
        // redeem rewards
        vm.warp(block.timestamp + WEEK / 2);
        uint256 balanceBefore = token.balanceOf(address(this));
        marketMaker.redeemRewards();
        uint256 balanceAfter = token.balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore);
    }
}
