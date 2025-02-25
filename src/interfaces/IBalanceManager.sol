// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../types/Currency.sol";

interface IBalanceManager {
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    event Withdrawal(address indexed user, uint256 indexed id, uint256 amount);
    event OperatorSet(address indexed operator, bool approved);
    event TransferFrom(
        address indexed operator,
        address indexed sender,
        address indexed receiver,
        uint256 id,
        uint256 amount,
        uint256 feeAmount
    );

    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error TransferError(address user, Currency currency, uint256 amount);
    error ZeroAmount();
    error UnauthorizedOperator(address operator);

    function getBalance(address user, Currency currency) external view returns (uint256);

    function deposit(Currency currency, uint256 amount) external;

    function deposit(Currency currency, uint256 amount, address user) external;

    function withdraw(Currency currency, uint256 amount) external;

    function withdraw(Currency currency, uint256 amount, address user) external;

    function lock(address user, Currency currency, uint256 amount) external returns (bool);

    function unlock(address user, Currency currency, uint256 amount) external returns (bool);

    function transferLockedFrom(
        address sender,
        address receiver,
        Currency currency,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address receiver,
        Currency currency,
        uint256 amount
    ) external returns (bool);

    function setAuthorizedOperator(address operator, bool approved) external;

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external;
}
