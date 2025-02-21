// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Currency} from "./types/Currency.sol";

contract BalanceManager is Ownable, ReentrancyGuard {
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    event Withdrawal(address indexed user, uint256 indexed id, uint256 amount);
    event OperatorSet(address indexed operator, bool approved);
    event TransferFrom(
        address indexed operator, address indexed sender, address indexed receiver, uint256 id, uint256 amount
    );

    error InsufficientBalance(address user, uint256 id, uint256 want, uint256 have);
    error TransferError(address user, Currency currency, uint256 amount);
    error ZeroAmount();
    error UnauthorizedOperator(address operator);

    mapping(address owner => mapping(uint256 id => uint256 balance)) public balanceOf;
    mapping(address owner => mapping(address operator => mapping(uint256 id => uint256 amount))) public lockedBalanceOf;
    mapping(address => bool) private authorizedOperators; // To allow Routers or other contracts

    address private feeReceiver; // Address that receives fees

    uint256 public feeMaker; // e.g., 1 for 0.1%
    uint256 public feeTaker; // e.g., 5 for 0.5%
    uint256 constant FEE_UNIT = 1_000;

    constructor(address _owner, address _feeReceiver, uint256 _feeMaker, uint256 _feeTaker) Ownable(_owner) {
        feeReceiver = _feeReceiver;
        feeMaker = _feeMaker;
        feeTaker = _feeTaker;
    }

    // Allow owner to set authorized operators (e.g., Router)
    function setAuthorizedOperator(address operator, bool approved) external onlyOwner {
        authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external onlyOwner {
        feeMaker = _feeMaker;
        feeTaker = _feeTaker;
    }
    // Allow anyone to check  balanceOf

    function getBalance(address user, Currency currency) external view returns (uint256) {
        return balanceOf[user][currency.toId()];
    }

    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256) {
        return lockedBalanceOf[user][operator][currency.toId()];
    }

    function deposit(Currency currency, uint256 amount) external {
        deposit(currency, amount, msg.sender);
    }

    function deposit(Currency currency, uint256 amount, address user) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // Transfer tokens directly from the user to this contract
        currency.transferFrom(user, address(this), amount);

        // Credit the balance to the specified user
        balanceOf[user][currency.toId()] += amount;

        emit Deposit(user, currency.toId(), amount);
    }

    function withdraw(Currency currency, uint256 amount) external {
        withdraw(currency, amount, msg.sender);
    }

    // Withdraw tokens
    function withdraw(Currency currency, uint256 amount, address user) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if (balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, balanceOf[user][currency.toId()]);
        }
        balanceOf[user][currency.toId()] -= amount;
        currency.transfer(user, amount);
        emit Withdrawal(user, currency.toId(), amount);
    }

    function lock(address user, Currency currency, uint256 amount) external returns (bool) {
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if (balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, balanceOf[user][currency.toId()]);
        }
        balanceOf[user][currency.toId()] -= amount;
        lockedBalanceOf[user][msg.sender][currency.toId()] += amount;

        return true;
    }

    function unlock(address user, Currency currency, uint256 amount) external returns (bool) {
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if (lockedBalanceOf[user][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                user, currency.toId(), amount, lockedBalanceOf[user][msg.sender][currency.toId()]
            );
        }

        lockedBalanceOf[user][msg.sender][currency.toId()] -= amount;
        balanceOf[user][currency.toId()] += amount;

        return true;
    }

    function transferLockedFrom(address sender, address receiver, Currency currency, uint256 amount)
        external
        returns (bool)
    {
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if (lockedBalanceOf[sender][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                sender, currency.toId(), amount, lockedBalanceOf[sender][msg.sender][currency.toId()]
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * feeMaker / FEE_UNIT;
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        lockedBalanceOf[sender][msg.sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        balanceOf[feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(msg.sender, sender, receiver, currency.toId(), amount);

        return true;
    }

    function transferFrom(address sender, address receiver, Currency currency, uint256 amount)
        external
        returns (bool)
    {
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if (balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, balanceOf[sender][currency.toId()]);
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * feeTaker / FEE_UNIT;
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        balanceOf[sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        balanceOf[feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(msg.sender, sender, receiver, currency.toId(), amount);

        return true;
    }
}
