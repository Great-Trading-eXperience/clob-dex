// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import "../src/BalanceManager.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";

contract BalanceManagerTest is Test {
    BalanceManager private balanceManager;
    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user = address(0x789);
    address private operator = address(0xABC);
    Currency private weth;
    Currency private usdc;
    uint256 private feeMaker = 5; // 0.5%
    uint256 private feeTaker = 1; // 0.1%
    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 1_000_000_000_000;
    uint256 private initialBalanceWETH = 1000 ether;
    uint256 constant FEE_UNIT = 1000;

    function setUp() public {
        balanceManager = new BalanceManager(owner, feeReceiver, feeMaker, feeTaker);

        MockUSDC mockUSDC = new MockUSDC();
        MockWETH mockWETH = new MockWETH();

        mockUSDC.mint(user, initialBalanceUSDC);
        mockWETH.mint(user, initialBalanceWETH);
        usdc = Currency.wrap(address(mockUSDC));
        weth = Currency.wrap(address(mockWETH));

        vm.deal(user, initialBalance);
        vm.deal(operator, initialBalance);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        assertEq(userBalance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);
        balanceManager.withdraw(weth, withdrawAmount);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        assertEq(userBalance, depositAmount - withdrawAmount);
    }

    function testLock() public {
        uint256 depositAmount = 100 ether;
        uint256 lockAmount = 40 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        uint256 userLockedBalance = balanceManager.getLockedBalance(user, operator, weth);
        assertEq(userBalance, depositAmount - lockAmount);
        assertEq(userLockedBalance, lockAmount);
    }

    function testUnlock() public {
        uint256 depositAmount = 100 ether;
        uint256 lockAmount = 40 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        balanceManager.unlock(user, weth, lockAmount);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        uint256 userLockedBalance = balanceManager.getLockedBalance(user, operator, weth);
        assertEq(userBalance, depositAmount);
        assertEq(userLockedBalance, 0);
    }

    function testTransferLockedFrom() public {
        uint256 depositAmount = 100 ether;
        uint256 lockAmount = 50 ether;
        address receiver = address(0xFED);

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        balanceManager.transferLockedFrom(user, receiver, weth, lockAmount);
        vm.stopPrank();

        uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
        assertEq(receiverBalance, lockAmount * (FEE_UNIT - feeMaker) / FEE_UNIT);
    }

    function testTransferFrom() public {
        uint256 depositAmount = 100 ether;
        uint256 transfer = 40 ether;
        address receiver = address(0xFED);

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.transferFrom(user, receiver, weth, transfer);
        vm.stopPrank();

        uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
        assertEq(receiverBalance, transfer * (FEE_UNIT - feeTaker) / FEE_UNIT);
    }
}
