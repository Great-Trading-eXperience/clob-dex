// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../GTXRouter.sol";

/// @custom:oz-upgrades-from GTXRouter
contract GTXRouterV2 is GTXRouter {
    function getVersion() external pure returns (string memory) {
        return "GTXRouter V2";
    }
}
