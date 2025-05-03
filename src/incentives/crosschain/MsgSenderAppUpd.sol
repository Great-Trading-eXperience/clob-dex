// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IMsgSendEndpoint} from "../../interfaces/IMsgSendEndpoint.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// solhint-disable no-empty-blocks

abstract contract MsgSenderAppUpd is OwnableUpgradeable {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    error InsufficientFeeToSendMsg(uint256 balance, uint256 fee);

    struct MsgSenderStorage {
        uint256 approxDstExecutionGas;
        EnumerableMap.UintToAddressMap destinationContracts;
    }

    bytes32 private constant MSG_SENDER_STORAGE = keccak256("gtx.crosschain.msgsender.storage");

    function _getMsgSenderStorage() internal pure returns (MsgSenderStorage storage $) {
        bytes32 slot = MSG_SENDER_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    IMsgSendEndpoint public immutable msgSendEndpoint;

    modifier refundUnusedEth() {
        _;
        if (address(this).balance > 0) {
            Address.sendValue(payable(msg.sender), address(this).balance);
        }
    }

    constructor(
        address _msgSendEndpoint
    ) {
        msgSendEndpoint = IMsgSendEndpoint(_msgSendEndpoint);
    }

    function __MsgSenderAppUpd_init(
        uint256 _approxDstExecutionGas
    ) internal {
        _getMsgSenderStorage().approxDstExecutionGas = _approxDstExecutionGas;
    }

    function _sendMessage(uint256 chainId, bytes memory message) internal {
        MsgSenderStorage storage $ = _getMsgSenderStorage();

        assert($.destinationContracts.contains(chainId));
        address toAddr = $.destinationContracts.get(chainId);
        uint256 estimatedGasAmount = $.approxDstExecutionGas;
        uint256 fee = msgSendEndpoint.calcFee(toAddr, chainId, message, estimatedGasAmount);
        // LM contracts won't hold ETH on its own so this is fine
        if (address(this).balance < fee) {
            revert InsufficientFeeToSendMsg(address(this).balance, fee);
        }
        msgSendEndpoint.sendMessage{value: fee}(toAddr, chainId, message, estimatedGasAmount);
    }

    function addDestinationContract(
        address _address,
        uint256 _chainId
    ) external payable onlyOwner {
        _getMsgSenderStorage().destinationContracts.set(_chainId, _address);
    }

    function setApproxDstExecutionGas(
        uint256 gas
    ) external onlyOwner {
        _getMsgSenderStorage().approxDstExecutionGas = gas;
    }

    function getAllDestinationContracts()
        public
        view
        returns (uint256[] memory chainIds, address[] memory addrs)
    {
        MsgSenderStorage storage $ = _getMsgSenderStorage();
        uint256 length = $.destinationContracts.length();
        chainIds = new uint256[](length);
        addrs = new address[](length);

        for (uint256 i = 0; i < length; ++i) {
            (chainIds[i], addrs[i]) = $.destinationContracts.at(i);
        }
    }

    function _getSendMessageFee(
        uint256 chainId,
        bytes memory message
    ) internal view returns (uint256) {
        MsgSenderStorage storage $ = _getMsgSenderStorage();
        return msgSendEndpoint.calcFee(
            $.destinationContracts.get(chainId), chainId, message, $.approxDstExecutionGas
        );
    }
}
