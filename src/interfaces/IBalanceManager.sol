// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBalanceManager {
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdrawal(address indexed user, address indexed token, uint256 amount);
    event BalanceUpdated(address indexed user, address indexed token, uint256 amount);
    event OperatorSet(address indexed user, address indexed operator, bool approved);

    error InsufficientBalance(address user, address token, uint256 want, uint256 have);
    error TransferError(address user, address token, uint256 amount);
    error ZeroAmount();
    error UnauthorizedOperator(address user, address operator);

    function getBalance(address user, address token) external view returns (uint256);

    function getLockedBalance(address user, address operator, address token) external view returns (uint256);

    function deposit(address token, uint256 amount) external;

    function withdraw(address token, uint256 amount) external;
}
