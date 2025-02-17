// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC6909} from "./IERC6909.sol";

/// @notice Interface for ERC6909Lock, extending the ERC6909 interface
interface IERC6909Lock is IERC6909 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UnauthorizedOperator(address user, address operator);
    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TransferLocked(
        address indexed operator, address indexed sender, address indexed receiver, uint256 id, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Locks an amount of an id for a user.
    /// @param user The address of the user.
    /// @param id The id of the token.
    /// @param amount The amount of the token to lock.
    /// @return bool True, always, unless the function reverts
    function lock(address user, uint256 id, uint256 amount) external returns (bool);

    /// @notice Unlocks an amount of an id for a user.
    /// @param user The address of the user.
    /// @param id The id of the token.
    /// @param amount The amount of the token to unlock.
    /// @return bool True, always, unless the function reverts
    function unlock(address user, uint256 id, uint256 amount) external returns (bool);

    /// @notice Transfers a locked amount of an id from a sender to a receiver.
    /// @param sender The address of the sender.
    /// @param receiver The address of the receiver.
    /// @param id The id of the token.
    /// @param amount The amount of the token.
    /// @return bool True, always, unless the function reverts
    function transferLockedFrom(address sender, address receiver, uint256 id, uint256 amount) external returns (bool);
}
