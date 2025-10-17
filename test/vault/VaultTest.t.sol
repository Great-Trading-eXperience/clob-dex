// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../src/vaults/Vault.sol";
import "../../src/vaults/interfaces/IVault.sol";
import "../../src/mocks/MockLendingPool.sol";
import "../../src/mocks/MockUSDC.sol";

contract VaultTest is Test {
    Vault private vault;
    MockLendingPool private lendingPool;
    MockUSDC private token;

    address private chainBalanceManager = address(0x123);
    address private user = address(0x456);
    address private notManager = address(0x789);

    uint256 private initialBalance = 1_000_000e6; // 1M USDC

    function setUp() public {
        token = new MockUSDC();
        lendingPool = new MockLendingPool();

        // Deploy vault
        vault = new Vault(address(token), chainBalanceManager, address(lendingPool));

        // Mint tokens to chainBalanceManager for testing
        token.mint(chainBalanceManager, initialBalance);

        // Approve vault to spend chainBalanceManager's tokens
        vm.prank(chainBalanceManager);
        token.approve(address(vault), type(uint256).max);
    }

    function test_Initialize() public {
        assertEq(vault.asset(), address(token));
        assertEq(vault.chainBalanceManager(), chainBalanceManager);
        assertEq(vault.lendingPool(), address(lendingPool));
    }

    function test_Deposit() public {
        uint256 depositAmount = 1000e6;

        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        assertEq(vault.totalDeposits(), depositAmount);
        assertEq(token.balanceOf(address(vault)), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_DepositRevertIfNotManager() public {
        uint256 depositAmount = 1000e6;

        token.mint(notManager, depositAmount);

        vm.prank(notManager);
        token.approve(address(vault), depositAmount);

        vm.prank(notManager);
        vm.expectRevert(IVault.OnlyChainBalanceManager.selector);
        vault.deposit(depositAmount);
    }

    function test_DepositRevertIfZeroAmount() public {
        vm.prank(chainBalanceManager);
        vm.expectRevert(IVault.ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_Withdraw() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 400e6;

        // Deposit first
        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        // Withdraw
        vm.prank(chainBalanceManager);
        vault.withdraw(withdrawAmount, user);

        assertEq(vault.totalDeposits(), depositAmount - withdrawAmount);
        assertEq(token.balanceOf(user), withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
    }

    function test_WithdrawRevertIfNotManager() public {
        uint256 depositAmount = 1000e6;

        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        vm.prank(notManager);
        vm.expectRevert(IVault.OnlyChainBalanceManager.selector);
        vault.withdraw(100e6, user);
    }

    function test_WithdrawRevertIfZeroAmount() public {
        vm.prank(chainBalanceManager);
        vm.expectRevert(IVault.ZeroAmount.selector);
        vault.withdraw(0, user);
    }

    function test_WithdrawRevertIfZeroAddress() public {
        vm.prank(chainBalanceManager);
        vm.expectRevert(IVault.ZeroAddress.selector);
        vault.withdraw(100e6, address(0));
    }

    function test_DepositToYieldProtocol() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 600e6;

        // Deposit to vault first
        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        // Deposit to yield protocol
        vm.prank(chainBalanceManager);
        vault.depositToYieldProtocol(yieldAmount);

        assertEq(vault.assetsInYieldProtocol(), yieldAmount);
        assertEq(vault.idleAssets(), depositAmount - yieldAmount);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_DepositToYieldProtocolRevertIfNotManager() public {
        vm.prank(notManager);
        vm.expectRevert(IVault.OnlyChainBalanceManager.selector);
        vault.depositToYieldProtocol(100e6);
    }

    function test_DepositToYieldProtocolRevertIfInsufficientBalance() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 1500e6; // More than deposited

        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        vm.prank(chainBalanceManager);
        vm.expectRevert(IVault.InsufficientBalance.selector);
        vault.depositToYieldProtocol(yieldAmount);
    }

    function test_WithdrawFromYieldProtocol() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 600e6;
        uint256 withdrawYieldAmount = 300e6;

        // Deposit to vault and yield protocol
        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        vm.prank(chainBalanceManager);
        vault.depositToYieldProtocol(yieldAmount);

        // Withdraw from yield protocol
        vm.prank(chainBalanceManager);
        vault.withdrawFromYieldProtocol(withdrawYieldAmount);

        assertEq(vault.assetsInYieldProtocol(), yieldAmount - withdrawYieldAmount);
        assertEq(vault.idleAssets(), depositAmount - yieldAmount + withdrawYieldAmount);
    }

    function test_WithdrawFromYieldProtocolRevertIfNotManager() public {
        vm.prank(notManager);
        vm.expectRevert(IVault.OnlyChainBalanceManager.selector);
        vault.withdrawFromYieldProtocol(100e6);
    }

    function test_WithdrawFromYieldProtocolRevertIfInsufficientBalance() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 600e6;

        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        vm.prank(chainBalanceManager);
        vault.depositToYieldProtocol(yieldAmount);

        vm.prank(chainBalanceManager);
        vm.expectRevert(IVault.InsufficientBalance.selector);
        vault.withdrawFromYieldProtocol(800e6); // More than in yield
    }

    function test_WithdrawAutoWithdrawsFromYieldIfNeeded() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 800e6;
        uint256 withdrawAmount = 600e6;

        // Deposit to vault and yield protocol
        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        vm.prank(chainBalanceManager);
        vault.depositToYieldProtocol(yieldAmount);

        // Idle assets: 200e6, need to withdraw 600e6
        // Should automatically withdraw 400e6 from yield
        vm.prank(chainBalanceManager);
        vault.withdraw(withdrawAmount, user);

        assertEq(token.balanceOf(user), withdrawAmount);
        assertEq(vault.assetsInYieldProtocol(), 400e6); // 800 - 400 = 400
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
    }

    function test_YieldGeneration() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 1000e6;

        // Deposit to vault and yield protocol
        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        vm.prank(chainBalanceManager);
        vault.depositToYieldProtocol(yieldAmount);

        // Fast forward time to generate yield
        vm.warp(block.timestamp + 365 days);

        // Accrue yield in lending pool
        lendingPool.accrueYield(address(token), address(vault));

        // Check balance in lending pool (should have yield)
        uint256 balanceInPool = lendingPool.balanceOf(address(token), address(vault));
        assertGt(balanceInPool, yieldAmount); // Should be greater due to yield

        // Withdraw principal from yield protocol (the lending pool will return principal + yield)
        // The vault tracks assetsInYield as the principal amount deposited
        uint256 principalInYield = vault.assetsInYieldProtocol();

        vm.prank(chainBalanceManager);
        vault.withdrawFromYieldProtocol(principalInYield);

        // Total assets should now include yield (idle balance should be > depositAmount)
        assertGt(vault.totalAssets(), depositAmount);
        assertGt(vault.idleAssets(), depositAmount); // Idle assets includes principal + yield
    }

    function test_MultipleDepositsAndWithdrawals() public {
        uint256 firstDeposit = 500e6;
        uint256 secondDeposit = 300e6;
        uint256 firstWithdraw = 200e6;
        uint256 secondWithdraw = 100e6;

        // First deposit
        vm.prank(chainBalanceManager);
        vault.deposit(firstDeposit);
        assertEq(vault.totalDeposits(), firstDeposit);

        // Second deposit
        vm.prank(chainBalanceManager);
        vault.deposit(secondDeposit);
        assertEq(vault.totalDeposits(), firstDeposit + secondDeposit);

        // First withdraw
        vm.prank(chainBalanceManager);
        vault.withdraw(firstWithdraw, user);
        assertEq(vault.totalDeposits(), firstDeposit + secondDeposit - firstWithdraw);

        // Second withdraw
        vm.prank(chainBalanceManager);
        vault.withdraw(secondWithdraw, user);
        assertEq(vault.totalDeposits(), firstDeposit + secondDeposit - firstWithdraw - secondWithdraw);

        assertEq(token.balanceOf(user), firstWithdraw + secondWithdraw);
    }

    function test_TotalAssetsCalculation() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 600e6;

        vm.prank(chainBalanceManager);
        vault.deposit(depositAmount);

        // Before yield deposit
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.idleAssets(), depositAmount);
        assertEq(vault.assetsInYieldProtocol(), 0);

        // After yield deposit
        vm.prank(chainBalanceManager);
        vault.depositToYieldProtocol(yieldAmount);

        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.idleAssets(), 400e6);
        assertEq(vault.assetsInYieldProtocol(), yieldAmount);
    }
}
