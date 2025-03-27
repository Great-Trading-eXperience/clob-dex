// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {Currency} from "./types/Currency.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {console} from "forge-std/console.sol";

contract BalanceManager is IBalanceManager, Ownable, ReentrancyGuard {
    mapping(address owner => mapping(uint256 id => uint256 balance))
        public balanceOf;
    mapping(address owner => mapping(address operator => mapping(uint256 id => uint256 amount)))
        public lockedBalanceOf;
    mapping(address owner => mapping(address operator => mapping(uint256 id => mapping(address vault => uint256 amount))))
        public lockedBalanceOfVault;
    mapping(address => bool) private authorizedOperators; // To allow Routers or other contracts

    address private feeReceiver; // Address that receives fees

    uint256 public feeMaker; // e.g., 1 for 0.1%
    uint256 public feeTaker; // e.g., 5 for 0.5%
    uint256 constant FEE_UNIT = 1000;

    constructor(
        address _owner,
        address _feeReceiver,
        uint256 _feeMaker,
        uint256 _feeTaker
    ) Ownable(_owner) {
        feeReceiver = _feeReceiver;
        feeMaker = _feeMaker;
        feeTaker = _feeTaker;
    }

    // Allow owner to set authorized operators (e.g., Router)
    function setAuthorizedOperator(
        address operator,
        bool approved
    ) external onlyOwner {
        authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external onlyOwner {
        feeMaker = _feeMaker;
        feeTaker = _feeTaker;
    }
    // Allow anyone to check  balanceOf

    function getBalance(
        address user,
        Currency currency
    ) external view returns (uint256) {
        return balanceOf[user][currency.toId()];
    }

    function getLockedBalance(
        address user,
        address operator,
        Currency currency
    ) external view returns (uint256) {
        return lockedBalanceOf[user][operator][currency.toId()];
    }

    function getLockedBalanceOfVault(
        address user,
        address operator,
        Currency currency,
        address vault
    ) external view returns (uint256) {
        // console.log("[getLockedBalanceOfVault]");
        // console.log("user:", user);
        // console.log("operator:", operator);
        // console.log("currency:", Currency.unwrap(currency));
        // console.log("vault:", vault);
        return lockedBalanceOfVault[user][operator][currency.toId()][vault];
    }

    function deposit(Currency currency, uint256 amount) external {
        deposit(currency, amount, msg.sender);
    }

    function deposit(
        Currency currency,
        uint256 amount,
        address user
    ) public nonReentrant {
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
    function withdraw(
        Currency currency,
        uint256 amount,
        address user
    ) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if (balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(
                user,
                currency.toId(),
                amount,
                balanceOf[user][currency.toId()]
            );
        }
        balanceOf[user][currency.toId()] -= amount;
        currency.transfer(user, amount);
        emit Withdrawal(user, currency.toId(), amount);
    }

    function lock(
        address user,
        Currency currency,
        address vault,
        uint256 amount
    ) external returns (bool) {
        console.log("[lock]");
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if (balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(
                user,
                currency.toId(),
                amount,
                balanceOf[user][currency.toId()]
            );
        }
        balanceOf[user][currency.toId()] -= amount;

        if (vault != address(0)) {
            address token = Currency.unwrap(currency);

            require(ERC4626(vault).asset() == token, "Invalid vault for token");

            IERC20(token).approve(vault, amount);
            uint256 shares = ERC4626(vault).deposit(amount, address(this));
            IERC20(vault).approve(msg.sender, shares);

            console.log("Initial locked balance of user:", lockedBalanceOfVault[user][msg.sender][currency.toId()][vault]);

            lockedBalanceOfVault[user][msg.sender][currency.toId()][
                vault
            ] += shares;

            console.log("user:", user);
            console.log("operator:", msg.sender);
            console.log("Currency:", Currency.unwrap(currency));
            console.log("Vault:", vault);
            console.log("Amount:", amount);
            console.log("Shares:", shares);
            console.log("Last locked balance of user:", lockedBalanceOfVault[user][msg.sender][currency.toId()][vault]);

            lockedBalanceOf[user][msg.sender][currency.toId()] += amount;
        } else {
            console.log("Locked balance of user:", user);
            console.log("Locked balance of msg.sender:", msg.sender);
            console.log("Currency:", Currency.unwrap(currency));
            console.log("Amount:", amount);

            lockedBalanceOf[user][msg.sender][currency.toId()] += amount;
        }

        return true;
    }

    function unlock(
        address user,
        Currency currency,
        address vault,
        uint256 amount
    ) external returns (bool) {
        console.log("[unlock]");
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if (vault != address(0)) {
            uint256 shares = ERC4626(vault).previewDeposit(amount);

            if (
                lockedBalanceOfVault[user][msg.sender][currency.toId()][vault] <
                shares
            ) {
                revert InsufficientBalance(
                    user,
                    currency.toId(),
                    amount,
                    ERC4626(vault).previewRedeem(shares)
                );
            }

            console.log("user:", user);
            console.log("operator:", msg.sender);
            console.log("Currency:", Currency.unwrap(currency));
            console.log("Vault:", vault);
            console.log("Amount:", amount);
            console.log("Shares:", shares);

            lockedBalanceOfVault[user][msg.sender][currency.toId()][
                vault
            ] -= shares;
            console.log("Locked balance of user:", lockedBalanceOfVault[user][msg.sender][currency.toId()][vault]);
            lockedBalanceOf[user][msg.sender][currency.toId()] -= amount;
            balanceOf[user][currency.toId()] += amount;
        } else {
            if (lockedBalanceOf[user][msg.sender][currency.toId()] < amount) {
                revert InsufficientBalance(
                    user,
                    currency.toId(),
                    amount,
                    lockedBalanceOf[user][msg.sender][currency.toId()]
                );
            }

            lockedBalanceOf[user][msg.sender][currency.toId()] -= amount;
            balanceOf[user][currency.toId()] += amount;
        }

        return true;
    }

    function transferLockedFrom(
        address sender,
        address receiver,
        Currency currency,
        uint256 amount,
        address vault
    ) external returns (bool) {
        console.log("[transferLockedFrom]");
        console.log("sender address:", sender);
        console.log("msg.sender (operator):", msg.sender);
        console.log("currency address:", MockToken(Currency.unwrap(currency)).symbol());
        console.log("amount:", amount);
        
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        uint256 lockedBalance = 0;

        if (vault != address(0)) { 
            uint256 shares = lockedBalanceOfVault[sender][msg.sender][currency.toId()][vault];
            lockedBalance = ERC4626(vault).previewRedeem(shares);
        } else {
            lockedBalance = lockedBalanceOf[sender][msg.sender][currency.toId()];
        }

        console.log("locked balance:", lockedBalanceOf[sender][msg.sender][currency.toId()]);
        
        if (lockedBalance < amount) {
            revert InsufficientBalance(
                sender,
                currency.toId(),
                amount,
                lockedBalance
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = (amount * feeTaker) / FEE_UNIT;
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        if (vault != address(0)) {
            uint256 shares = lockedBalanceOfVault[sender][msg.sender][currency.toId()][vault];
            console.log("shares:", shares);
            console.log("balance of vault:", lockedBalanceOfVault[sender][msg.sender][currency.toId()][vault]);
            lockedBalanceOfVault[sender][msg.sender][currency.toId()][vault] -= shares;
            lockedBalanceOf[sender][msg.sender][currency.toId()] -= amount;
            balanceOf[receiver][currency.toId()] += amount - feeAmount;
        } else {
            lockedBalanceOf[sender][msg.sender][currency.toId()] -= amount;
            balanceOf[receiver][currency.toId()] += amount - feeAmount;
        }
        
        balanceOf[feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(
            msg.sender,
            sender,
            receiver,
            currency.toId(),
            amount,
            feeAmount
        );

        return true;
    }

    function transferFrom(
        address sender,
        address receiver,
        Currency currency,
        uint256 amount
    ) external returns (bool) {
        console.log("[transferFrom]");
        if (!authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if (balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                sender,
                currency.toId(),
                amount,
                balanceOf[sender][currency.toId()]
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = (amount * feeMaker) / FEE_UNIT;
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        balanceOf[sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        balanceOf[receiver][currency.toId()] += amountAfterFee;

        console.log("receiver", receiver);
        console.log("currency", currency.toId());
        console.log("amount", amount);

        // Transfer the fee to the feeReceiver
        balanceOf[feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(
            msg.sender,
            sender,
            receiver,
            currency.toId(),
            amount,
            feeAmount
        );

        return true;
    }
}
