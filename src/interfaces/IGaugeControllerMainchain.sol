// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IGaugeController.sol";

interface IGaugeControllerMainchain is IGaugeController {
    function updateVotingResults(
        uint128 wTime,
        address[] calldata markets,
        uint256[] calldata pendleSpeeds
    ) external;
}
