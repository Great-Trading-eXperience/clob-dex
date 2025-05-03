// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./GaugeControllerBaseUpg.sol";
import "../crosschain/MsgReceiverAppUpd.sol";

// solhint-disable no-empty-blocks

contract GaugeControllerSidechainUpg is GaugeControllerBaseUpg, MsgReceiverAppUpd {
    constructor(
        address _token,
        address _marketMakerFactory,
        address _msgReceiveEndpointUpg
    )
        GaugeControllerBaseUpg(_token, _marketMakerFactory)
        MsgReceiverAppUpd(_msgReceiveEndpointUpg)
    {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    function _executeMessage(
        bytes memory message
    ) internal virtual override {
        (uint128 wTime, address[] memory markets, uint256[] memory tokenAmounts) =
            abi.decode(message, (uint128, address[], uint256[]));
        _receiveVotingResults(wTime, markets, tokenAmounts);
    }
}
