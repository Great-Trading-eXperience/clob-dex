// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../libraries/PMath.sol";

import "../libraries/WeekMath.sol";

import "../../interfaces/IGaugeController.sol";
import "../../interfaces/IMarketMakerFactory.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @dev Gauge controller provides no write function to any party other than voting controller
 * @dev Gauge controller will receive (lpTokens[], pendle per sec[]) from voting controller and
 * set it directly to contract state
 * @dev All of the core data in this function are set to private to prevent unintended assignments
 * on inheriting contracts
 */
abstract contract GaugeControllerBaseUpg is IGaugeController, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using PMath for uint256;

    error GAUGE_CONTROLLER__NotMarketMaker(address marketMaker);
    error GAUGE_CONTROLLER__ArrayLengthMismatch();

    struct MarketRewardData {
        uint128 tokenPerSec;
        uint128 accumulatedToken;
        uint128 lastUpdated;
        uint128 incentiveEndsAt;
    }

    struct GaugeControllerStorage {
        mapping(address => MarketRewardData) rewardData;
        mapping(uint128 => bool) epochRewardReceived;
        mapping(address => bool) isValidMarket;
    }

    bytes32 private constant GAUGE_CONTROLLER_STORAGE = keccak256("gtx.gauge.controller.storage");

    function _getGaugeControllerStorage()
        internal
        pure
        returns (GaugeControllerStorage storage $)
    {
        bytes32 slot = GAUGE_CONTROLLER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    uint128 internal constant WEEK = 1 weeks;

    // solhint-disable immutable-vars-naming
    address public immutable token;
    IMarketMakerFactory public immutable marketMakerFactory;

    modifier onlyMarketMaker() {
        if (marketMakerFactory.isValidMarketMaker(msg.sender)) {
            _;
        } else {
            revert GAUGE_CONTROLLER__NotMarketMaker(msg.sender);
        }
    }

    constructor(address _token, address _marketMakerFactory) {
        token = _token;
        marketMakerFactory = IMarketMakerFactory(_marketMakerFactory);
    }

    /**
     * @notice claim the rewards allocated by gaugeController
     * @dev only pendle market can call this
     */
    function redeemMarketReward() external onlyMarketMaker {
        address market = msg.sender;
        GaugeControllerStorage storage $ = _getGaugeControllerStorage();

        $.rewardData[market] = _getUpdatedMarketReward(market);

        uint256 amount = $.rewardData[market].accumulatedToken;
        if (amount != 0) {
            $.rewardData[market].accumulatedToken = 0;
            IERC20(token).safeTransfer(market, amount);
        }

        emit MarketClaimReward(market, amount);
    }

    function fundToken(
        uint256 amount
    ) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawToken(
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function isValidMarket(
        address market
    ) external view returns (bool) {
        return _getGaugeControllerStorage().isValidMarket[market];
    }

    function rewardData(
        address market
    )
        external
        view
        returns (
            uint128 tokenPerSec,
            uint128 accumulatedToken,
            uint128 lastUpdated,
            uint128 incentiveEndsAt
        )
    {
        GaugeControllerStorage storage $ = _getGaugeControllerStorage();
        return (
            $.rewardData[market].tokenPerSec,
            $.rewardData[market].accumulatedToken,
            $.rewardData[market].lastUpdated,
            $.rewardData[market].incentiveEndsAt
        );
    }

    /**
     * @notice receive voting results from VotingController. Only the first message for a timestamp
     * will be accepted, all subsequent messages will be ignored
     */
    function _receiveVotingResults(
        uint128 wTime,
        address[] memory markets,
        uint256[] memory tokenAmounts
    ) internal {
        if (markets.length != tokenAmounts.length) revert GAUGE_CONTROLLER__ArrayLengthMismatch();

        GaugeControllerStorage storage $ = _getGaugeControllerStorage();

        if ($.epochRewardReceived[wTime]) return; // only accept the first message for the wTime
        $.epochRewardReceived[wTime] = true;

        for (uint256 i = 0; i < markets.length; ++i) {
            _addRewardsToMarket(markets[i], tokenAmounts[i].Uint128());
        }

        emit ReceiveVotingResults(wTime, markets, tokenAmounts);
    }

    /**
     * @notice merge the additional rewards with the existing rewards
     * @dev this function will calc the total amount of Pendle that hasn't been factored into
     * accumulatedToken yet, combined them with the additional tokenAmount, then divide them
     * equally over the next one week
     */
    function _addRewardsToMarket(address market, uint128 tokenAmount) internal {
        MarketRewardData memory rwd = _getUpdatedMarketReward(market);
        uint128 leftover = (rwd.incentiveEndsAt - rwd.lastUpdated) * rwd.tokenPerSec;
        uint128 newSpeed = (leftover + tokenAmount) / WEEK;

        GaugeControllerStorage storage $ = _getGaugeControllerStorage();

        $.rewardData[market] = MarketRewardData({
            tokenPerSec: newSpeed,
            accumulatedToken: rwd.accumulatedToken,
            lastUpdated: uint128(block.timestamp),
            incentiveEndsAt: uint128(block.timestamp) + WEEK
        });

        emit UpdateMarketReward(market, newSpeed, uint128(block.timestamp) + WEEK);
    }

    /**
     * @notice get the updated state of the market, to the current time with all the undistributed
     * Pendle distributed to the accumulatedToken
     * @dev expect to update accumulatedToken & lastUpdated in MarketRewardData
     */
    function _getUpdatedMarketReward(
        address market
    ) internal view returns (MarketRewardData memory) {
        GaugeControllerStorage storage $ = _getGaugeControllerStorage();
        MarketRewardData memory rwd = $.rewardData[market];
        uint128 newLastUpdated = uint128(PMath.min(uint128(block.timestamp), rwd.incentiveEndsAt));
        rwd.accumulatedToken += rwd.tokenPerSec * (newLastUpdated - rwd.lastUpdated);
        rwd.lastUpdated = newLastUpdated;
        return rwd;
    }
}
