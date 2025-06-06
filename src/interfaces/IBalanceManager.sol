// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

interface IBalanceManager {
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    event Withdrawal(address indexed user, uint256 indexed id, uint256 amount);
    event Lock(address indexed user, uint256 indexed id, uint256 amount);
    event Unlock(address indexed user, uint256 indexed id, uint256 amount);
    event OperatorSet(address indexed operator, bool approved);
    event PoolManagerSet(address indexed poolManager);
    event TransferFrom(
        address indexed operator,
        address indexed sender,
        address indexed receiver,
        uint256 id,
        uint256 amount,
        uint256 feeAmount
    );
    event TransferLockedFrom(
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
    error UnauthorizedCaller(address caller);

    function getBalance(address user, Currency currency) external view returns (uint256);

    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256);

    function deposit(Currency currency, uint256 amount, address sender, address user) external;

    function depositAndLock(
        Currency currency,
        uint256 amount,
        address user,
        address ordrBook
    ) external returns (uint256);

    function withdraw(Currency currency, uint256 amount) external;

    function withdraw(Currency currency, uint256 amount, address user) external;

    function lock(address user, Currency currency, uint256 amount) external;

    function lock(address user, Currency currency, uint256 amount, address orderBook) external;

    function unlock(address user, Currency currency, uint256 amount) external;

    function transferOut(address sender, address receiver, Currency currency, uint256 amount) external;

    function transferLockedFrom(address sender, address receiver, Currency currency, uint256 amount) external;

    function transferFrom(address sender, address receiver, Currency currency, uint256 amount) external;

    function setAuthorizedOperator(address operator, bool approved) external;

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external;
}
