// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import {Test, console} from "forge-std/Test.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract BalanceManagerTest is Test {
    BalanceManager private balanceManager;
    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user = address(0x789);
    address private operator = address(0xABC);
    Currency private weth;
    Currency private usdc;
    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 1_000_000_000_000;
    uint256 private initialBalanceWETH = 1000 ether;
    uint256 constant FEE_UNIT = 1000;

    function setUp() public {
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy beaconProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );

        balanceManager = BalanceManager(address(beaconProxy));

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
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        uint256 userBalance = balanceManager.getBalance(user, weth);
        assertEq(userBalance, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 100 ether;
        uint256 withdrawAmount = 50 ether;

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
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
        balanceManager.deposit(weth, depositAmount, user, user);
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
        balanceManager.deposit(weth, depositAmount, user, user);
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
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.lock(user, weth, lockAmount);
        balanceManager.transferLockedFrom(user, receiver, weth, lockAmount);
        vm.stopPrank();

        uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
        assertEq(receiverBalance, lockAmount * (FEE_UNIT - feeTaker) / FEE_UNIT);
    }

    function testTransferFrom() public {
        uint256 depositAmount = 100 ether;
        uint256 transfer = 40 ether;
        address receiver = address(0xFED);

        vm.startPrank(user);
        IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
        balanceManager.deposit(weth, depositAmount, user, user);
        vm.stopPrank();

        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(operator, true);
        vm.stopPrank();

        vm.startPrank(operator);
        balanceManager.transferFrom(user, receiver, weth, transfer);
        vm.stopPrank();

        uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
        assertEq(receiverBalance, transfer * (FEE_UNIT - feeMaker) / FEE_UNIT);
    }
    
    // function testMarketMakerVaultExemption() public {
    //     address marketMakerVault = address(0xDEAD);
    //     uint256 depositAmount = 100 ether;
    //     uint256 transfer = 40 ether;
    //     address receiver = address(0xFED);
        
    //     // Setup market maker vault
    //     vm.startPrank(owner);
    //     balanceManager.setMarketMakerVault(marketMakerVault, true);
    //     balanceManager.setAuthorizedOperator(operator, true);
    //     vm.stopPrank();
        
    //     // Verify market maker vault status
    //     bool isExempt = balanceManager.isMarketMakerVault(marketMakerVault);
    //     assertTrue(isExempt);
        
    //     // Deposit funds to market maker vault
    //     vm.startPrank(marketMakerVault);
    //     IERC20(Currency.unwrap(weth)).mint(marketMakerVault, depositAmount);
    //     IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
    //     balanceManager.deposit(weth, depositAmount, marketMakerVault, marketMakerVault);
    //     vm.stopPrank();
        
    //     // Transfer from market maker vault (should have no fees)
    //     vm.startPrank(operator);
    //     balanceManager.transferFrom(marketMakerVault, receiver, weth, transfer);
    //     vm.stopPrank();
        
    //     // Verify receiver got full amount (no fees deducted)
    //     uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
    //     assertEq(receiverBalance, transfer, "Market maker vault should be exempt from fees");
    // }
    
    // function testMarketMakerVaultLockedExemption() public {
    //     address marketMakerVault = address(0xBEEF);
    //     uint256 depositAmount = 100 ether;
    //     uint256 lockAmount = 50 ether;
    //     address receiver = address(0xFED);
        
    //     // Setup market maker vault
    //     vm.startPrank(owner);
    //     balanceManager.setMarketMakerVault(marketMakerVault, true);
    //     balanceManager.setAuthorizedOperator(operator, true);
    //     vm.stopPrank();
        
    //     // Deposit funds to market maker vault
    //     vm.startPrank(marketMakerVault);
    //     IERC20(Currency.unwrap(weth)).mint(marketMakerVault, depositAmount);
    //     IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
    //     balanceManager.deposit(weth, depositAmount, marketMakerVault, marketMakerVault);
    //     vm.stopPrank();
        
    //     // Lock and transfer from market maker vault (should have no fees)
    //     vm.startPrank(operator);
    //     balanceManager.lock(marketMakerVault, weth, lockAmount);
    //     balanceManager.transferLockedFrom(marketMakerVault, receiver, weth, lockAmount);
    //     vm.stopPrank();
        
    //     // Verify receiver got full amount (no fees deducted)
    //     uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
    //     assertEq(receiverBalance, lockAmount, "Market maker vault should be exempt from fees on locked transfers");
    // }
    
    // function testMarketMakerVaultToggle() public {
    //     address marketMakerVault = address(0xCAFE);
    //     uint256 depositAmount = 100 ether;
    //     uint256 transfer = 40 ether;
    //     address receiver = address(0xFED);
        
    //     // Setup market maker vault
    //     vm.startPrank(owner);
    //     balanceManager.setMarketMakerVault(marketMakerVault, true);
    //     balanceManager.setAuthorizedOperator(operator, true);
    //     vm.stopPrank();
        
    //     // Deposit funds to market maker vault
    //     vm.startPrank(marketMakerVault);
    //     IERC20(Currency.unwrap(weth)).mint(marketMakerVault, depositAmount);
    //     IERC20(Currency.unwrap(weth)).approve(address(balanceManager), depositAmount);
    //     balanceManager.deposit(weth, depositAmount, marketMakerVault, marketMakerVault);
    //     vm.stopPrank();
        
    //     // Transfer from market maker vault (should have no fees)
    //     vm.startPrank(operator);
    //     balanceManager.transferFrom(marketMakerVault, receiver, weth, transfer);
    //     vm.stopPrank();
        
    //     // Verify receiver got full amount (no fees deducted)
    //     uint256 receiverBalance = balanceManager.getBalance(receiver, weth);
    //     assertEq(receiverBalance, transfer, "Market maker vault should be exempt from fees");
        
    //     // Now remove the exemption
    //     vm.startPrank(owner);
    //     balanceManager.setMarketMakerVault(marketMakerVault, false);
    //     vm.stopPrank();
        
    //     // Verify market maker vault status is now false
    //     bool isExempt = balanceManager.isMarketMakerVault(marketMakerVault);
    //     assertFalse(isExempt);
        
    //     // Transfer again, this time fees should be applied
    //     vm.startPrank(operator);
    //     balanceManager.transferFrom(marketMakerVault, receiver, weth, transfer);
    //     vm.stopPrank();
        
    //     // Verify receiver got amount minus fees
    //     uint256 expectedBalance = transfer + transfer * (FEE_UNIT - feeMaker) / FEE_UNIT;
    //     assertEq(balanceManager.getBalance(receiver, weth), expectedBalance, "Fees should be applied after exemption is removed");
    // }
}
