// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../../src/faucet/Faucet.sol";
import "../../src/mocks/MockToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FaucetTest is Test {
    Faucet public faucet;
    MockToken public weth;
    MockToken public usdc;

    // Events from Faucet contract
    event AddToken(address token);
    event UpdateFaucetAmount(uint256 amount);
    event UpdateFaucetCooldown(uint256 cooldown);
    event RequestToken(address requester, address receiver, address token);
    event DepositToken(address depositor, address token, uint256 amount);

    address anotherAddress;
    address user1;
    address user2;
    address constant NATIVE_TOKEN = address(0);

    function setUp() public {
        faucet = new Faucet();
        faucet.initialize(address(this));
        faucet.updateFaucetAmount(1 * 10 ** 18);
        faucet.updateFaucetCooldown(60);

        weth = new MockToken("WETH", "WETH", 18);
        usdc = new MockToken("USDC", "USDC", 6);

        anotherAddress = vm.addr(2);
        user1 = vm.addr(3);
        user2 = vm.addr(4);
        
        // Mint tokens for testing
        weth.mint(address(this), 100 * 10**18);
        weth.mint(user1, 10 * 10**18);
        usdc.mint(address(this), 100000 * 10**6);
        usdc.mint(user1, 10000 * 10**6);
        
        // Fund the contract with ETH for native token testing
        vm.deal(address(faucet), 10 ether);
        vm.deal(user1, 5 ether);
    }

    function testOwnerCanAddToken() public {
        vm.expectEmit(false, false, false, true);

        emit AddToken(address(weth));

        faucet.addToken(address(weth));

        bool isExist = false;

        for(uint256 i = 0; i < faucet.getAvailableTokensLength(); i++) {
            if (faucet.getAvailableToken(i) == address(weth)) {
                isExist = true;
            }
        }

        assertEq(isExist, true);
    }

    function testNonOwnerCannotAddToken() public {
        vm.prank(anotherAddress);
        vm.expectRevert();

        faucet.addToken(address(weth));

        bool isExist = false;

        for(uint256 i = 0; i < faucet.getAvailableTokensLength(); i++) {
            if (faucet.getAvailableToken(i) == address(weth)) {
                isExist = true;
            }
        }

        assertEq(isExist, false);
    }

    function testOwnerCanUpdateFaucetAmount() public {
        vm.expectEmit(false, false, false, true);

        uint256 faucetAmount = 100;

        emit UpdateFaucetAmount(faucetAmount);

        faucet.updateFaucetAmount(faucetAmount);

        assertEq(faucet.getFaucetAmount(), faucetAmount);
    }

    function testNonOwnerCannotUpdateFaucetAmount() public {
        vm.prank(anotherAddress);
        vm.expectRevert();

        uint256 faucetAmount = 100;

        faucet.updateFaucetAmount(faucetAmount);
    }

    function testOwnerCanUpdateFaucetCooldown() public {
        vm.expectEmit(false, false, false, true);

        uint256 faucetCooldown = 100;

        emit UpdateFaucetCooldown(faucetCooldown);

        faucet.updateFaucetCooldown(faucetCooldown);

        assertEq(faucet.getCooldown(), faucetCooldown);
    }

    function testNonOwnerCannotUpdateFaucetCooldown() public {
        vm.prank(anotherAddress);
        vm.expectRevert();

        uint256 faucetCooldown = 100;

        faucet.updateFaucetCooldown(faucetCooldown);
    }

    // === TOKEN ADDITION TESTS ===

    function testCannotAddSameTokenTwice() public {
        faucet.addToken(address(weth));
        
        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyExists(address)", address(weth)));
        faucet.addToken(address(weth));
    }

    // === ERC20 TOKEN TESTS ===

    function testDepositERC20Token() public {
        faucet.addToken(address(weth));
        
        uint256 depositAmount = 5 * 10**18;
        weth.approve(address(faucet), depositAmount);
        
        vm.expectEmit(true, true, true, true);
        emit DepositToken(address(this), address(weth), depositAmount);
        
        faucet.depositToken(address(weth), depositAmount);
        
        assertEq(weth.balanceOf(address(faucet)), depositAmount);
    }

    function testCannotDepositUnsupportedERC20Token() public {
        uint256 depositAmount = 5 * 10**18;
        weth.approve(address(faucet), depositAmount);
        
        vm.expectRevert(abi.encodeWithSignature("TokenNotSupported(address)", address(weth)));
        faucet.depositToken(address(weth), depositAmount);
    }

    function testCannotDepositZeroAmountERC20() public {
        faucet.addToken(address(weth));
        
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        faucet.depositToken(address(weth), 0);
    }

    function testCannotDepositERC20WithETHSent() public {
        faucet.addToken(address(weth));
        
        uint256 depositAmount = 5 * 10**18;
        weth.approve(address(faucet), depositAmount);
        
        vm.expectRevert(abi.encodeWithSignature("IncorrectNativeAmount()"));
        faucet.depositToken{value: 1 ether}(address(weth), depositAmount);
    }

    function testRequestERC20Token() public {
        // Setup: add token and deposit some
        faucet.addToken(address(weth));
        uint256 depositAmount = 10 * 10**18;
        weth.approve(address(faucet), depositAmount);
        faucet.depositToken(address(weth), depositAmount);
        
        vm.expectEmit(true, true, true, true);
        emit RequestToken(address(this), user1, address(weth));
        
        faucet.requestToken(user1, address(weth));
        
        assertEq(weth.balanceOf(user1), 1 * 10**18); // faucetAmount
        assertEq(weth.balanceOf(address(faucet)), depositAmount - 1 * 10**18);
    }

    function testCannotRequestERC20WithoutFaucetAmount() public {
        faucet.updateFaucetAmount(0);
        faucet.addToken(address(weth));
        
        vm.expectRevert(abi.encodeWithSignature("FaucetAmountNotSet()"));
        faucet.requestToken(user1, address(weth));
    }

    function testCannotRequestERC20WithoutCooldown() public {
        faucet.updateFaucetCooldown(0);
        faucet.addToken(address(weth));
        
        vm.expectRevert(abi.encodeWithSignature("FaucetCooldownNotSet()"));
        faucet.requestToken(user1, address(weth));
    }

    function testCannotRequestERC20WithInsufficientBalance() public {
        faucet.addToken(address(weth));
        // No tokens deposited
        
        vm.expectRevert(abi.encodeWithSignature("InsufficientFaucetBalance(uint256,uint256)", 1 * 10**18, 0));
        faucet.requestToken(user1, address(weth));
    }

    // === NATIVE TOKEN TESTS ===

    function testDepositNativeToken() public {
        uint256 depositAmount = 2 ether;
        uint256 initialBalance = address(faucet).balance;
        
        vm.expectEmit(true, true, true, true);
        emit DepositToken(address(this), NATIVE_TOKEN, depositAmount);
        
        faucet.depositToken{value: depositAmount}(NATIVE_TOKEN, depositAmount);
        
        assertEq(address(faucet).balance, initialBalance + depositAmount);
    }

    function testDepositNativeTokenConvenienceFunction() public {
        uint256 depositAmount = 1 ether;
        uint256 initialBalance = address(faucet).balance;
        
        vm.expectEmit(true, true, true, true);
        emit DepositToken(address(this), NATIVE_TOKEN, depositAmount);
        
        faucet.depositNative{value: depositAmount}();
        
        assertEq(address(faucet).balance, initialBalance + depositAmount);
    }

    function testCannotDepositNativeWithIncorrectAmount() public {
        vm.expectRevert(abi.encodeWithSignature("IncorrectNativeAmount()"));
        faucet.depositToken{value: 2 ether}(NATIVE_TOKEN, 1 ether);
    }

    function testCannotDepositZeroNative() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        faucet.depositNative{value: 0}();
    }

    function testRequestNativeToken() public {
        uint256 initialBalance = address(faucet).balance;
        uint256 userInitialBalance = user1.balance;
        
        vm.expectEmit(true, true, true, true);
        emit RequestToken(address(this), user1, NATIVE_TOKEN);
        
        faucet.requestToken(user1, NATIVE_TOKEN);
        
        assertEq(user1.balance, userInitialBalance + 1 ether); // faucetAmount
        assertEq(address(faucet).balance, initialBalance - 1 ether);
    }

    function testRequestNativeTokenConvenienceFunction() public {
        uint256 initialBalance = address(faucet).balance;
        uint256 userInitialBalance = user1.balance;
        
        vm.expectEmit(true, true, true, true);
        emit RequestToken(address(this), user1, NATIVE_TOKEN);
        
        faucet.requestNative(user1);
        
        assertEq(user1.balance, userInitialBalance + 1 ether);
        assertEq(address(faucet).balance, initialBalance - 1 ether);
    }

    function testCannotRequestNativeWithInsufficientBalance() public {
        // Drain the faucet
        faucet.updateFaucetAmount(20 ether); // More than available
        
        vm.expectRevert(abi.encodeWithSignature("InsufficientNativeBalance(uint256,uint256)", 20 ether, 10 ether));
        faucet.requestToken(user1, NATIVE_TOKEN);
    }

    function testReceiveFunctionDepositsNative() public {
        uint256 depositAmount = 0.5 ether;
        uint256 initialBalance = address(faucet).balance;
        
        vm.expectEmit(true, true, true, true);
        emit DepositToken(address(this), NATIVE_TOKEN, depositAmount);
        
        (bool success,) = payable(address(faucet)).call{value: depositAmount}("");
        assertTrue(success);
        
        assertEq(address(faucet).balance, initialBalance + depositAmount);
    }

    // === COOLDOWN TESTS ===

    function testCooldownEnforcedForERC20() public {
        // Setup
        faucet.addToken(address(weth));
        uint256 depositAmount = 10 * 10**18;
        weth.approve(address(faucet), depositAmount);
        faucet.depositToken(address(weth), depositAmount);
        
        // First request should succeed
        vm.prank(user1);
        faucet.requestToken(user1, address(weth));
        
        // Second request immediately should fail
        uint256 availableAt = block.timestamp + 60; // cooldown period
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("CooldownNotPassed(uint256)", availableAt));
        faucet.requestToken(user1, address(weth));
    }

    function testCooldownEnforcedForNative() public {
        // First request should succeed
        vm.prank(user1);
        faucet.requestToken(user1, NATIVE_TOKEN);
        
        // Second request immediately should fail
        uint256 availableAt = block.timestamp + 60; // cooldown period
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("CooldownNotPassed(uint256)", availableAt));
        faucet.requestToken(user1, NATIVE_TOKEN);
    }

    function testCooldownAllowsRequestAfterTime() public {
        faucet.addToken(address(weth));
        uint256 depositAmount = 10 * 10**18;
        weth.approve(address(faucet), depositAmount);
        faucet.depositToken(address(weth), depositAmount);
        
        // First request
        vm.prank(user1);
        faucet.requestToken(user1, address(weth));
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + 61);
        
        // Second request should succeed
        vm.prank(user1);
        faucet.requestToken(user1, address(weth));
        
        assertEq(weth.balanceOf(user1), 2 * 10**18); // Two faucet amounts
    }

    function testFirstTimeUserBypassesCooldown() public {
        // New user (user2) should be able to request immediately
        vm.prank(user2);
        faucet.requestToken(user2, NATIVE_TOKEN);
        
        assertEq(user2.balance, 1 ether);
    }

    // === VIEW FUNCTION TESTS ===

    function testGetNativeBalance() public view {
        uint256 expectedBalance = address(faucet).balance;
        assertEq(faucet.getNativeBalance(), expectedBalance);
    }

    function testGetTokenBalanceForNative() public view {
        uint256 expectedBalance = address(faucet).balance;
        assertEq(faucet.getTokenBalance(NATIVE_TOKEN), expectedBalance);
    }

    function testGetTokenBalanceForERC20() public {
        faucet.addToken(address(weth));
        uint256 depositAmount = 5 * 10**18;
        weth.approve(address(faucet), depositAmount);
        faucet.depositToken(address(weth), depositAmount);
        
        assertEq(faucet.getTokenBalance(address(weth)), depositAmount);
    }

    function testIsNativeToken() public view {
        assertTrue(faucet.isNativeToken(NATIVE_TOKEN));
        assertFalse(faucet.isNativeToken(address(weth)));
    }

    function testGetLastRequestTime() public {
        vm.prank(user1);
        faucet.requestToken(user1, NATIVE_TOKEN);
        
        vm.prank(user1);
        uint256 lastRequestTime = faucet.getLastRequestTime();
        assertEq(lastRequestTime, block.timestamp);
    }

    function testGetAvailabilityTime() public {
        vm.prank(user1);
        faucet.requestToken(user1, NATIVE_TOKEN);
        
        vm.prank(user1);
        uint256 availabilityTime = faucet.getAvailabilityTime();
        assertEq(availabilityTime, block.timestamp + 60);
    }

    // === HELPER FUNCTIONS ===
    
    function testGetCurrentTimestamp() public view {
        assertEq(faucet.getCurrentTimestamp(), block.timestamp);
    }

    function testGetFaucetAmount() public view {
        assertEq(faucet.getFaucetAmount(), 1 * 10**18);
    }

    function testGetCooldown() public view {
        assertEq(faucet.getCooldown(), 60);
    }

    function testGetAvailableTokensLength() public {
        assertEq(faucet.getAvailableTokensLength(), 0);
        
        faucet.addToken(address(weth));
        assertEq(faucet.getAvailableTokensLength(), 1);
        
        faucet.addToken(address(usdc));
        assertEq(faucet.getAvailableTokensLength(), 2);
    }

    function testGetAvailableToken() public {
        faucet.addToken(address(weth));
        faucet.addToken(address(usdc));
        
        assertEq(faucet.getAvailableToken(0), address(weth));
        assertEq(faucet.getAvailableToken(1), address(usdc));
    }
}
