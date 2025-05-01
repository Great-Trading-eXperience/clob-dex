// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../BalanceManager.sol";

/// @custom:oz-upgrades-from BalanceManager
contract BalanceManagerV2 is BalanceManager {
    function getVersion() external pure returns (string memory) {
        return "BalanceManager V2";
    }
}
