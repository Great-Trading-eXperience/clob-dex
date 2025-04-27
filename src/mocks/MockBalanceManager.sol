// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "../libraries/Currency.sol";

contract MockBalanceManager {
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    event Withdrawal(address indexed user, uint256 indexed id, uint256 amount);
    event OperatorSet(address indexed operator, bool approved);
    event TransferLocked(
        address indexed operator, address indexed sender, address indexed receiver, uint256 id, uint256 amount
    );

    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error TransferError(address user, Currency currency, uint256 amount);
    error ZeroAmount();
    error UnauthorizedOperator(address operator);

    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public lockedBalanceOf;
    mapping(address => bool) private authorizedOperators;

    constructor(
        address _onwer
    ) {}

    function deposit(Currency currency, uint256 amount, address user) external {
        balanceOf[user][currency.toId()] += amount;
        emit Deposit(user, currency.toId(), amount);
    }

    function withdraw(Currency currency, uint256 amount, address user) external {
        require(balanceOf[user][currency.toId()] >= amount, "Insufficient balance");
        balanceOf[user][currency.toId()] -= amount;
        emit Withdrawal(user, currency.toId(), amount);
    }

    function setAuthorizedOperator(address operator, bool approved) external {
        authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    function lock(address, /* user */ Currency, /* currency */ uint256 /* amount */ ) external pure returns (bool) {
        return true;
    }

    function unlock(address, /* user */ Currency, /* currency */ uint256 /* amount */ ) external pure returns (bool) {
        return true;
    }

    function transferLockedFrom(
        address, /* sender */
        address, /* receiver */
        Currency, /* currency */
        uint256 /* amount */
    ) external pure returns (bool) {
        return true;
    }

    function transferFrom(
        address, /* sender */
        address, /* receiver */
        Currency, /* currency */
        uint256 /* amount */
    ) external pure returns (bool) {
        return true;
    }
}
