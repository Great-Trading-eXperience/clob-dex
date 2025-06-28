// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../../src/faucet/Faucet.sol";
import "../../src/mocks/MockToken.sol";

contract FaucetTest is Test {
    Faucet public faucet;
    MockToken public weth;
    MockToken public usdc;

    event AddToken(address token);
    event UpdateFaucetAmount(uint256 amount);
    event UpdateFaucetCooldown(uint256 cooldown);
    event RequestToken(address requester, address receiver, address token);
    event DepositToken(address depositor, address token, uint256 amount);

    address anotherAddress;

    function setUp() public {
        faucet = new Faucet();
        faucet.updateFaucetAmount(1 * 10 ** 18);
        faucet.updateFaucetCooldown(60);

        weth = new MockToken("WETH", "WETH", 18);
        usdc = new MockToken("USDC", "USDC", 6);

        anotherAddress = vm.addr(2);
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

    function testNonOwnerCanAddToken() public {
        vm.prank(anotherAddress);
        vm.expectRevert(bytes( "Only owner can invoke this method"));

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

    function testNonOwnerCanUpdateFaucetAmount() public {
        vm.prank(anotherAddress);
        vm.expectRevert(bytes( "Only owner can invoke this method"));

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

    function testNonOwnerCanUpdateFaucetCooldown() public {
        vm.prank(anotherAddress);
        vm.expectRevert(bytes( "Only owner can invoke this method"));

        uint256 faucetCooldown = 100;

        faucet.updateFaucetCooldown(faucetCooldown);
    }
}
