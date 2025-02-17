// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC6909} from "./ERC6909.sol";
import {IERC6909Lock} from "./interfaces/external/IERC6909Lock.sol";

/// @notice ERC6909Claims inherits ERC6909 and implements an internal burnFrom function
abstract contract ERC6909Lock is ERC6909, IERC6909Lock {
    // event TransferLocked(
    //     address indexed operator, address indexed sender, address indexed receiver, uint256 id, uint256 amount
    // );

    mapping(address owner => mapping(address operator => mapping(uint256 id => uint256 amount))) public lockedBalanceOf;

    function lock(address user, uint256 id, uint256 amount) public virtual returns (bool) {
        if (!isOperator[user][msg.sender]) {
            revert UnauthorizedOperator(user, msg.sender);
        }
        if (balanceOf[user][id] < amount) {
            revert InsufficientBalance(user, id, amount, balanceOf[user][id]);
        }
        balanceOf[user][id] -= amount;
        lockedBalanceOf[user][msg.sender][id] += amount;

        return true;
    }

    function unlock(address user, uint256 id, uint256 amount) public virtual returns (bool) {
        if (!isOperator[user][msg.sender]) {
            revert UnauthorizedOperator(user, msg.sender);
        }
        if (lockedBalanceOf[user][msg.sender][id] < amount) {
            revert InsufficientBalance(user, id, amount, lockedBalanceOf[user][msg.sender][id]);
        }

        lockedBalanceOf[user][msg.sender][id] -= amount;
        balanceOf[user][id] += amount;

        return true;
    }

    function transferLockedFrom(address sender, address receiver, uint256 id, uint256 amount)
        public
        virtual
        returns (bool)
    {
        if (!isOperator[sender][msg.sender]) {
            revert UnauthorizedOperator(sender, msg.sender);
        }
        if (lockedBalanceOf[sender][msg.sender][id] < amount) {
            revert InsufficientBalance(sender, id, amount, lockedBalanceOf[sender][msg.sender][id]);
        }

        lockedBalanceOf[sender][msg.sender][id] -= amount;
        balanceOf[receiver][id] += amount;

        emit TransferLocked(msg.sender, sender, receiver, id, amount);

        return true;
    }
}
