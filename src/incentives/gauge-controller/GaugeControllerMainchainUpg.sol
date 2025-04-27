// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./GaugeControllerBaseUpg.sol";
import "../../interfaces/IGaugeControllerMainchain.sol";

contract GaugeControllerMainchainUpg is GaugeControllerBaseUpg, IGaugeControllerMainchain {
    error GAUGE_CONTROLLER__NotVotingController(address sender);

    address public immutable votingController;

    modifier onlyVotingController() {
        if (msg.sender != votingController) {
            revert GAUGE_CONTROLLER__NotVotingController(msg.sender);
        }
        _;
    }

    constructor(
        address _votingController,
        address _token,
        address _marketMakerFactory
    ) GaugeControllerBaseUpg(_token, _marketMakerFactory) {
        votingController = _votingController;
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    function updateVotingResults(
        uint128 wTime,
        address[] memory markets,
        uint256[] memory tokenSpeeds
    ) external onlyVotingController {
        _receiveVotingResults(wTime, markets, tokenSpeeds);
    }
}
