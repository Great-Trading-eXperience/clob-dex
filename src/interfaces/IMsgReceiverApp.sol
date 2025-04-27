// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

interface IMsgReceiverApp {
    function executeMessage(
        bytes calldata message
    ) external;
}
