// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IMsgReceiverApp.sol";

// solhint-disable no-empty-blocks

abstract contract MsgReceiverAppUpd is IMsgReceiverApp {
    error MsgNotFromReceiveEndpoint(address sender);

    address public immutable msgReceiveEndpoint;

    modifier onlyFromMsgReceiveEndpoint() {
        if (msg.sender != msgReceiveEndpoint) {
            revert MsgNotFromReceiveEndpoint(msg.sender);
        }
        _;
    }

    constructor(
        address _msgReceiveEndpoint
    ) {
        msgReceiveEndpoint = _msgReceiveEndpoint;
    }

    function executeMessage(
        bytes calldata message
    ) external virtual onlyFromMsgReceiveEndpoint {
        _executeMessage(message);
    }

    function _executeMessage(
        bytes memory message
    ) internal virtual;
}
