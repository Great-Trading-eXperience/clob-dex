// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../PoolManager.sol";

/// @custom:oz-upgrades-from PoolManager
contract PoolManagerV2 is PoolManager {
    function getVersion() external pure returns (string memory) {
        return "PoolManager V2";
    }
}
