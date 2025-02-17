// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

abstract contract BalanceManager is IBalanceManager {
    // event Deposit(address indexed user, address indexed token, uint256 amount);
    // event Withdrawal(address indexed user, address indexed token, uint256 amount);
    // event BalanceUpdated(address indexed user, address indexed token, uint256 amount);
    // event OperatorSet(address indexed user, address indexed operator, bool approved);

    // error InsufficientBalance(address user, address token, uint256 want, uint256 have);
    // error TransferError(address user, address token, uint256 amount);
    // error ZeroAmount();
    // error UnauthorizedOperator(address user, address operator);

    address private owner;

    mapping(address => mapping(address => bool)) private isOperator;
    mapping(address => mapping(address => uint256)) private balances;
    mapping(address => mapping(address => mapping(address => uint256))) private lockedBalances;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    constructor(address _owner) {}

    function getBalance(address user, address token) external view returns (uint256) {
        return balances[user][token];
    }

    function getLockedBalance(address user, address operator, address token) external view returns (uint256) {
        return lockedBalances[user][operator][token];
    }

    function deposit(address token, uint256 amount) external {
        if (amount == 0) {
            revert ZeroAmount();
        }
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        balances[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        if (balances[msg.sender][token] < amount) {
            revert InsufficientBalance(msg.sender, token, amount, balances[msg.sender][token]);
        }
        balances[msg.sender][token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
        emit Withdrawal(msg.sender, token, amount);
    }

    function setOperator(address operator, bool approved) external {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
    }

    function lock(address user, address operator, address token, uint256 amount) external {
        if (!isOperator[user][operator]) {
            revert UnauthorizedOperator(user, operator);
        }
        if (balances[user][token] < amount) {
            revert InsufficientBalance(user, token, amount, balances[user][token]);
        }
        balances[user][token] -= amount;
        lockedBalances[user][operator][token] += amount;
    }

    function unlock(address user, address operator, address token, uint256 amount) external {
        if (!isOperator[user][operator]) {
            revert UnauthorizedOperator(user, operator);
        }
        if (lockedBalances[user][operator][token] < amount) {
            revert InsufficientBalance(user, token, amount, lockedBalances[user][operator][token]);
        }
        lockedBalances[user][operator][token] -= amount;
        balances[user][token] += amount;
    }

    function transferLocked(address sender, address operator, address receiver, address token, uint256 amount)
        external
    {
        if (!isOperator[sender][operator]) {
            revert UnauthorizedOperator(sender, operator);
        }
        if (lockedBalances[sender][operator][token] < amount) {
            revert InsufficientBalance(sender, token, amount, lockedBalances[sender][operator][token]);
        }
        lockedBalances[sender][operator][token] -= amount;
        balances[receiver][token] += amount;
        emit BalanceUpdated(sender, token, amount);
    }
}
