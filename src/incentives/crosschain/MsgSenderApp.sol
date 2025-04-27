// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IMsgSendEndpoint} from "../../interfaces/IMsgSendEndpoint.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// solhint-disable no-empty-blocks

abstract contract MsgSenderApp is Ownable {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    error InsufficientFeeToSendMsg(uint256 balance, uint256 fee);

    uint256 public approxDstExecutionGas;

    IMsgSendEndpoint public immutable msgSendEndpoint;

    // destinationContracts mapping contains one address for each chainId only
    EnumerableMap.UintToAddressMap internal destinationContracts;

    modifier refundUnusedEth() {
        _;
        if (address(this).balance > 0) {
            Address.sendValue(payable(msg.sender), address(this).balance);
        }
    }

    constructor(address _msgSendEndpoint, uint256 _approxDstExecutionGas) Ownable(msg.sender) {
        msgSendEndpoint = IMsgSendEndpoint(_msgSendEndpoint);
        approxDstExecutionGas = _approxDstExecutionGas;
    }

    function _sendMessage(uint256 chainId, bytes memory message) internal {
        assert(destinationContracts.contains(chainId));
        address toAddr = destinationContracts.get(chainId);
        uint256 estimatedGasAmount = approxDstExecutionGas;
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
        destinationContracts.set(_chainId, _address);
    }

    function setApproxDstExecutionGas(
        uint256 gas
    ) external onlyOwner {
        approxDstExecutionGas = gas;
    }

    function getAllDestinationContracts()
        public
        view
        returns (uint256[] memory chainIds, address[] memory addrs)
    {
        uint256 length = destinationContracts.length();
        chainIds = new uint256[](length);
        addrs = new address[](length);

        for (uint256 i = 0; i < length; ++i) {
            (chainIds[i], addrs[i]) = destinationContracts.at(i);
        }
    }

    function _getSendMessageFee(
        uint256 chainId,
        bytes memory message
    ) internal view returns (uint256) {
        return msgSendEndpoint.calcFee(
            destinationContracts.get(chainId), chainId, message, approxDstExecutionGas
        );
    }
}
