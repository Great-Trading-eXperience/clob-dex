// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "../../src/vaults/GTXVault.sol";
import "../../src/vaults/VaultFactory.sol";
import "../../src/mocks/MockLendingPool.sol";
import "../../src/mocks/MockUSDC.sol";

contract GTXVaultTest is Test {
    GTXVault private vault;
    GTXVault private simpleVault;
    MockLendingPool private lendingPool;
    MockUSDC private usdc;
    MockUSDC private dai; // Second token for simple vault
    VaultFactory private vaultFactory;

    address private owner = address(0x123);
    address private user1 = address(0x456);
    address private user2 = address(0x789);

    uint256 private constant INITIAL_BALANCE = 10_000_000e6; // 10M tokens

    function setUp() public {
        // Deploy tokens
        usdc = new MockUSDC();
        dai = new MockUSDC(); // Use MockUSDC as DAI for simplicity

        // Deploy lending pool
        lendingPool = new MockLendingPool();

        // Deploy vault factory
        vaultFactory = new VaultFactory(owner);

        // Deploy GTXVault with lending pool for USDC
        vm.prank(owner);
        address vaultAddr = vaultFactory.deployGTXVault(
            address(usdc),
            "GTX USDC Vault",
            "gtxUSDC",
            address(lendingPool)
        );
        vault = GTXVault(vaultAddr);

        // Deploy simple vault without lending pool for DAI
        vm.prank(owner);
        address simpleVaultAddr = vaultFactory.deploySimpleVault(
            address(dai),
            "Simple DAI Vault",
            "sDAI"
        );
        simpleVault = GTXVault(simpleVaultAddr);

        // Mint tokens to users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(address(this), INITIAL_BALANCE);

        dai.mint(user1, INITIAL_BALANCE);
        dai.mint(user2, INITIAL_BALANCE);
        dai.mint(address(this), INITIAL_BALANCE);
    }

    // ========== ERC4626 COMPLIANCE TESTS ==========

    function test_ERC4626_Asset() public view {
        assertEq(vault.asset(), address(usdc));
        assertEq(simpleVault.asset(), address(dai));
    }

    function test_ERC4626_Deposit() public {
        uint256 depositAmount = 1000e6; // 1000 USDC

        usdc.approve(address(vault), depositAmount);

        uint256 shares = vault.deposit(depositAmount, address(this));

        assertEq(shares, depositAmount); // 1:1 on first deposit
        assertEq(vault.balanceOf(address(this)), shares);
        assertEq(vault.totalAssets(), depositAmount);
    }

    function test_ERC4626_Withdraw() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, address(this));

        uint256 withdrawn = vault.withdraw(depositAmount, address(this), address(this));

        assertEq(withdrawn, shares);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(address(this)), INITIAL_BALANCE);
    }

    function test_ERC4626_Mint() public {
        uint256 sharesToMint = 1000e6;

        usdc.approve(address(vault), sharesToMint);

        uint256 assets = vault.mint(sharesToMint, address(this));

        assertEq(assets, sharesToMint);
        assertEq(vault.balanceOf(address(this)), sharesToMint);
    }

    function test_ERC4626_Redeem() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        uint256 assets = vault.redeem(depositAmount, address(this), address(this));

        assertEq(assets, depositAmount);
        assertEq(vault.balanceOf(address(this)), 0);
    }

    // ========== LENDING POOL INTEGRATION TESTS ==========

    function test_DepositToYieldProtocol() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 800e6; // 80%

        // First deposit to vault
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        // Then move to yield protocol
        vm.prank(owner);
        vault.depositToYieldProtocol(yieldAmount);

        assertEq(vault.assetsInYield(), yieldAmount);
        assertEq(vault.idleAssets(), depositAmount - yieldAmount);
        assertEq(vault.totalAssets(), depositAmount); // Total unchanged
    }

    function test_DepositToYieldProtocolRevertIfNotOwner() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        vm.prank(user1);
        vm.expectRevert();
        vault.depositToYieldProtocol(100e6);
    }

    function test_DepositToYieldProtocolRevertIfInsufficientIdle() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        vm.prank(owner);
        vm.expectRevert(GTXVault.InsufficientIdleAssets.selector);
        vault.depositToYieldProtocol(2000e6); // More than available
    }

    function test_WithdrawFromYieldProtocol() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 800e6;

        // Deposit to vault then to yield protocol
        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        vm.prank(owner);
        vault.depositToYieldProtocol(yieldAmount);

        // Withdraw from yield protocol
        vm.prank(owner);
        vault.withdrawFromYieldProtocol(400e6);

        assertEq(vault.assetsInYield(), 400e6); // 800 - 400
        assertEq(vault.idleAssets(), 600e6); // 200 + 400
    }

    function test_WithdrawFromYieldProtocolRevertIfNotOwner() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        vm.prank(owner);
        vault.depositToYieldProtocol(800e6);

        vm.prank(user1);
        vm.expectRevert();
        vault.withdrawFromYieldProtocol(100e6);
    }

    // ========== YIELD GENERATION TESTS ==========

    function test_YieldAccrual() public {
        uint256 depositAmount = 1000e6;
        uint256 yieldAmount = 800e6;

        // Deposit and move to lending pool
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, address(this));

        vm.prank(owner);
        vault.depositToYieldProtocol(yieldAmount);

        // Fast forward time to accrue yield (1 day)
        vm.warp(block.timestamp + 1 days);

        // Check that totalAssets increased (yield accrued)
        uint256 totalAssetsAfterYield = vault.totalAssets();
        assertTrue(totalAssetsAfterYield > depositAmount, "Yield should have accrued");

        // Share value should have increased
        uint256 assetsPerShare = vault.convertToAssets(1e6); // Assets per 1 share
        assertTrue(assetsPerShare > 1e6, "Share value should increase with yield");
    }

    function test_ShareValueIncreasesWithYield() public {
        uint256 depositAmount = 1000e6;

        // User1 deposits
        vm.startPrank(user1);
        usdc.approve(address(vault), depositAmount);
        uint256 shares1 = vault.deposit(depositAmount, user1);
        vm.stopPrank();

        // Move to yield protocol
        vm.prank(owner);
        vault.depositToYieldProtocol(800e6);

        // Fast forward and accrue yield
        vm.warp(block.timestamp + 30 days);

        uint256 totalAssetsWithYield = vault.totalAssets();
        assertTrue(totalAssetsWithYield > depositAmount);

        // User2 deposits same amount but gets fewer shares (higher share price)
        vm.startPrank(user2);
        usdc.approve(address(vault), depositAmount);
        uint256 shares2 = vault.deposit(depositAmount, user2);
        vm.stopPrank();

        assertTrue(shares2 < shares1, "User2 should get fewer shares due to increased share value");
    }

    function test_SimulateYieldWithAddYield() public {
        uint256 depositAmount = 1000e6;
        uint256 simulatedYield = 50e6;

        // Deposit to vault
        dai.approve(address(simpleVault), depositAmount);
        uint256 shares = simpleVault.deposit(depositAmount, address(this));

        uint256 totalAssetsBefore = simpleVault.totalAssets();

        // Simulate yield
        dai.mint(address(this), simulatedYield);
        dai.approve(address(simpleVault), simulatedYield);
        simpleVault.addYield(simulatedYield);

        uint256 totalAssetsAfter = simpleVault.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore + simulatedYield);

        // Share value increased (allow for rounding)
        uint256 assetsPerShare = simpleVault.convertToAssets(shares);
        assertTrue(assetsPerShare >= depositAmount + simulatedYield - 1);
        assertTrue(assetsPerShare <= depositAmount + simulatedYield + 1);
    }

    // ========== REBALANCING SCENARIO TESTS ==========

    function test_RebalancingScenario() public {
        uint256 depositAmount = 10_000e6; // 10k USDC

        // ChainBalanceManager deposits to vault
        usdc.approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, address(this));

        // Rebalance: 80% to yield, 20% idle
        vm.prank(owner);
        vault.depositToYieldProtocol(8000e6);

        assertEq(vault.idleAssets(), 2000e6); // 20% hot wallet
        assertEq(vault.assetsInYield(), 8000e6); // 80% in yield
        assertEq(vault.totalAssets(), depositAmount);

        // User withdrawal needs 3000 USDC (more than idle)
        uint256 withdrawAmount = 3000e6;
        uint256 sharesToRedeem = vault.convertToShares(withdrawAmount);

        // Vault automatically withdraws from lending pool if needed
        vm.prank(owner);
        vault.withdrawFromYieldProtocol(1000e6); // Get enough for withdrawal

        vault.redeem(sharesToRedeem, address(this), address(this));

        // Check final state
        assertTrue(vault.totalAssets() < depositAmount);
        assertEq(usdc.balanceOf(address(this)), INITIAL_BALANCE - depositAmount + withdrawAmount);
    }

    // ========== EDGE CASE TESTS ==========

    function test_DepositZero() public {
        // ERC4626 allows zero deposits (returns 0 shares)
        uint256 shares = vault.deposit(0, address(this));
        assertEq(shares, 0);
    }

    function test_WithdrawZero() public {
        // ERC4626 allows zero withdrawals (returns 0 shares)
        uint256 shares = vault.withdraw(0, address(this), address(this));
        assertEq(shares, 0);
    }

    function test_SimpleVaultWithoutLendingPool() public {
        uint256 depositAmount = 1000e6;

        dai.approve(address(simpleVault), depositAmount);
        simpleVault.deposit(depositAmount, address(this));

        // Should revert when trying to use lending pool functions
        vm.prank(owner);
        vm.expectRevert(GTXVault.ZeroAddress.selector);
        simpleVault.depositToYieldProtocol(100e6);
    }

    function test_SetLendingPool() public {
        address newLendingPool = address(0xABCD);

        vm.prank(owner);
        vault.setLendingPool(newLendingPool);

        assertEq(vault.lendingPool(), newLendingPool);
    }

    function test_SetLendingPoolRevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setLendingPool(address(0xABCD));
    }

    function test_EmergencyWithdraw() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        vm.prank(owner);
        vault.emergencyWithdraw(address(usdc), 500e6, user1);

        assertEq(usdc.balanceOf(user1), INITIAL_BALANCE + 500e6);
    }

    function test_EmergencyWithdrawRevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.emergencyWithdraw(address(usdc), 100e6, user1);
    }

    // ========== VIEW FUNCTION TESTS ==========

    function test_IdleAssets() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        assertEq(vault.idleAssets(), depositAmount);

        vm.prank(owner);
        vault.depositToYieldProtocol(600e6);

        assertEq(vault.idleAssets(), 400e6);
    }

    function test_AssetsInYieldProtocol() public {
        uint256 depositAmount = 1000e6;

        usdc.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));

        vm.prank(owner);
        vault.depositToYieldProtocol(800e6);

        // Fast forward to accrue yield
        vm.warp(block.timestamp + 10 days);

        uint256 assetsInYield = vault.assetsInYieldProtocol();
        assertTrue(assetsInYield > 800e6, "Should include accrued yield");
    }

    function test_VaultFactoryGetVaultInfo() public view {
        (
            address vaultAddr,
            string memory name,
            string memory symbol,
            uint256 totalAssets,
            uint256 totalSupply,
            uint256 assetsPerShare
        ) = vaultFactory.getVaultInfo(address(usdc));

        assertEq(vaultAddr, address(vault));
        assertEq(name, "GTX USDC Vault");
        assertEq(symbol, "gtxUSDC");
        assertEq(totalAssets, 0);
        assertEq(totalSupply, 0);
        assertEq(assetsPerShare, 1e18); // 1:1 when no shares
    }
}
