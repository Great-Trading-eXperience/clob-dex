// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IGaugeController {
    event MarketClaimReward(address indexed market, uint256 amount);

    event ReceiveVotingResults(uint128 indexed wTime, address[] markets, uint256[] pendleAmounts);

    event UpdateMarketReward(address indexed market, uint256 pendlePerSec, uint256 incentiveEndsAt);

    function fundToken(
        uint256 amount
    ) external;

    function withdrawToken(
        uint256 amount
    ) external;

    function token() external returns (address);

    function redeemMarketReward() external;

    function rewardData(
        address pool
    ) external view returns (uint128 pendlePerSec, uint128, uint128, uint128);
}
