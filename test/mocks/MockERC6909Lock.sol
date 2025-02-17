// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "../../src/PoolManager.sol";
import {ERC6909Lock} from "../../src/ERC6909Lock.sol";
// import {IERC6909Lock} from "../../src/interfaces/external/IERC6909Lock.sol";

/// @notice MockERC6909Lock inherits ERC6909 and implements an internal burnFrom function
contract MockERC6909Lock is ERC6909Lock {
    function lock(address, /*user*/ uint256, /*id*/ uint256 /*amount*/ ) public pure override returns (bool) {
        return true;
    }

    function unlock(address, /*user*/ uint256, /*id*/ uint256 /*amount*/ ) public pure override returns (bool) {
        return true;
    }

    function transferLockedFrom(address, /*sender*/ address, /*receiver*/ uint256, /*id*/ uint256 /*amount*/ )
        public
        pure
        override
        returns (bool)
    {
        return true;
    }
}
