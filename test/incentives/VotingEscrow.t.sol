// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {MockToken} from "../../src/mocks/MockToken.sol";
import {VotingEscrowMainchain} from "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VotingEscrowTest is Test {
    uint256 private constant WEEK = 1 weeks;

    MockToken public token;
    VotingEscrowMainchain public votingEscrow;

    function setUp() public {
        // mock token
        token = new MockToken("Test Token", "TEST", 18);
        token.mint(address(this), 1000e18);

        // voting escrow
        votingEscrow = new VotingEscrowMainchain(address(token), address(0), 1e6);
    }

    function test_increaseLockPositionAndBroadcast() public {
        uint128 amountToLock = 100e18;
        token.approve(address(votingEscrow), amountToLock);

        vm.warp(block.timestamp + (10 * WEEK));

        uint256 timeInWeeks = (block.timestamp / WEEK) * WEEK;

        uint256 inValidWTime = timeInWeeks + 26 * WEEK + 100;
        // increase lock position
        vm.expectRevert(
            abi.encodeWithSelector(
                VotingEscrowMainchain.InvalidWTime.selector, uint128(inValidWTime)
            )
        );
        votingEscrow.increaseLockPosition(amountToLock, uint128(inValidWTime));

        uint256 expiredTime = timeInWeeks - WEEK;
        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrowMainchain.ExpiryInThePast.selector, expiredTime)
        );
        votingEscrow.increaseLockPosition(amountToLock, uint128(expiredTime));

        uint256 exceededMaxTime = timeInWeeks + 105 weeks;
        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrowMainchain.VEExceededMaxLockTime.selector)
        );
        votingEscrow.increaseLockPosition(amountToLock, uint128(exceededMaxTime));

        // under 1 week
        uint256 InsufficientLockTime = timeInWeeks + WEEK;
        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrowMainchain.VEInsufficientLockTime.selector)
        );
        votingEscrow.increaseLockPosition(amountToLock, uint128(InsufficientLockTime));

        uint128 expiry = uint128(timeInWeeks + 52 * WEEK); // Lock 1 year
        vm.expectRevert(abi.encodeWithSelector(VotingEscrowMainchain.VEZeroAmountLocked.selector));
        votingEscrow.increaseLockPosition(0, expiry);

        uint128 newVeBalance = votingEscrow.increaseLockPosition(amountToLock, expiry);
        (uint128 totalSupplyCurrent, uint128 account1VeBal) =
            votingEscrow.totalSupplyAndBalanceCurrent(address(this));
        assertEq(newVeBalance, totalSupplyCurrent);
        assertEq(newVeBalance, account1VeBal);

        (uint128 lockAmount, uint128 lockDuration) = votingEscrow.positionData(address(this));
        assertEq(lockAmount, amountToLock);
        assertEq(lockDuration, expiry);

        uint256 lockedBalance = token.balanceOf(address(votingEscrow));
        assertEq(lockedBalance, amountToLock);

        // check veBalance after 2 weeks
        uint256 veBalanceBefore = votingEscrow.balanceOf(address(this));
        vm.warp(block.timestamp + 2 * WEEK);
        uint256 veBalanceAfter = votingEscrow.balanceOf(address(this));
        assertLt(veBalanceAfter, veBalanceBefore);
    }
}
