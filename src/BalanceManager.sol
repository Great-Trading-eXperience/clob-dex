// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {ReentrancyGuardUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {Currency} from "./libraries/Currency.sol";
import {BalanceManagerStorage} from "./storages/BalanceManagerStorage.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BalanceManager is IBalanceManager, BalanceManagerStorage, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _feeReceiver,
        uint256 _feeMaker,
        uint256 _feeTaker
    ) public initializer {
        __Ownable_init(_owner);
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.feeReceiver = _feeReceiver;
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
        $.feeUnit = 1000;
    }

    function setPoolManager(
        address _poolManager
    ) external onlyOwner {
        getStorage().poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    // Allow owner to set authorized operators (e.g., Router)
    function setAuthorizedOperator(address operator, bool approved) external {
        Storage storage $ = getStorage();

        if (msg.sender != owner() && msg.sender != $.poolManager) {
            revert UnauthorizedCaller(msg.sender);
        }

        $.authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external onlyOwner {
        Storage storage $ = getStorage();
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
    }

    // Allow anyone to check balanceOf
    function getBalance(address user, Currency currency) external view returns (uint256) {
        return getStorage().balanceOf[user][currency.toId()];
    }

    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256) {
        return getStorage().lockedBalanceOf[user][operator][currency.toId()];
    }

    function deposit(Currency currency, uint256 amount, address sender, address user) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // Transfer tokens directly from the user to this contract
        currency.transferFrom(sender, address(this), amount);

        // Credit the balance to the specified user
        uint256 currencyId = currency.toId();

        unchecked {
            $.balanceOf[user][currencyId] += amount;
        }

        emit Deposit(user, currencyId, amount);
    }

    function depositAndLock(
        Currency currency,
        uint256 amount,
        address user,
        address orderBook
    ) external nonReentrant returns (uint256) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        // Verify if the caller is the user or an authorized operator
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // Transfer tokens directly from sender to this contract
        currency.transferFrom(user, address(orderBook), amount);

        // Credit directly to locked balance, bypassing the regular balance
        uint256 currencyId = currency.toId();

        unchecked {
            $.lockedBalanceOf[user][orderBook][currencyId] += amount;
        }

        emit Deposit(user, currencyId, amount);

        return amount;
    }

    function withdraw(Currency currency, uint256 amount) external {
        withdraw(currency, amount, msg.sender);
    }

    // Withdraw tokens
    function withdraw(Currency currency, uint256 amount, address user) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, $.balanceOf[user][currency.toId()]);
        }
        $.balanceOf[user][currency.toId()] -= amount;
        currency.transfer(user, amount);
        emit Withdrawal(user, currency.toId(), amount);
    }

    function lock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, msg.sender);
    }

    function lock(address user, Currency currency, uint256 amount, address orderBook) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, orderBook);
    }

    function _lock(address user, Currency currency, uint256 amount, address locker) private {
        Storage storage $ = getStorage();

        if ($.balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, $.balanceOf[user][currency.toId()]);
        }

        $.balanceOf[user][currency.toId()] -= amount;
        $.lockedBalanceOf[user][locker][currency.toId()] += amount;

        emit Lock(user, currency.toId(), amount);
    }

    function unlock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.lockedBalanceOf[user][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                user, currency.toId(), amount, $.lockedBalanceOf[user][msg.sender][currency.toId()]
            );
        }

        $.lockedBalanceOf[user][msg.sender][currency.toId()] -= amount;
        $.balanceOf[user][currency.toId()] += amount;

        emit Unlock(user, currency.toId(), amount);
    }

    function transferOut(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, $.balanceOf[sender][currency.toId()]);
        }

        IERC20(Currency.unwrap(currency)).transfer(receiver, amount);

        $.balanceOf[sender][currency.toId()] -= amount;
    }

    function transferLockedFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.lockedBalanceOf[sender][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                sender, currency.toId(), amount, $.lockedBalanceOf[sender][msg.sender][currency.toId()]
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeTaker / _feeUnit();
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        $.lockedBalanceOf[sender][msg.sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currency.toId()] += feeAmount;

        emit TransferLockedFrom(msg.sender, sender, receiver, currency.toId(), amount, feeAmount);
    }

    function transferFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, $.balanceOf[sender][currency.toId()]);
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeMaker / _feeUnit();
        require(feeAmount <= amount, "Fee exceeds the transfer amount");

        // Deduct fee and update balances
        $.balanceOf[sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(msg.sender, sender, receiver, currency.toId(), amount, feeAmount);
    }

    // Add public getters for fees and feeReceiver
    function feeMaker() external view returns (uint256) {
        return getStorage().feeMaker;
    }

    function feeTaker() external view returns (uint256) {
        return getStorage().feeTaker;
    }

    function feeReceiver() external view returns (address) {
        return getStorage().feeReceiver;
    }

    function getFeeUnit() external view returns (uint256) {
        return _feeUnit();
    }

    function _feeUnit() private view returns (uint256) {
        return getStorage().feeUnit;
    }
}
