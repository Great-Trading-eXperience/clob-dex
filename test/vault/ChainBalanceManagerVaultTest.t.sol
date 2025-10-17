// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../src/core/ChainBalanceManager.sol";
import "../../src/vaults/VaultFactory.sol";
import "../../src/vaults/Vault.sol";
import "../../src/mocks/MockLendingPool.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/core/interfaces/IChainBalanceManagerErrors.sol";

import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract MockMailbox {
    event Dispatch(uint32 destinationDomain, bytes32 recipient, bytes message);

    function dispatch(uint32 destinationDomain, bytes32 recipient, bytes calldata messageBody) external payable returns (bytes32) {
        emit Dispatch(destinationDomain, recipient, messageBody);
        return keccak256(messageBody);
    }
}

contract ChainBalanceManagerVaultTest is Test {
    ChainBalanceManager private chainBalanceManager;
    VaultFactory private vaultFactory;
    MockLendingPool private lendingPool;
    MockUSDC private usdc;
    MockMailbox private mailbox;

    address private owner = address(0x123);
    address private user1 = address(0x456);
    address private notOwner = address(0x789);

    uint256 private initialBalance = 10_000_000e6; // 10M USDC
    uint32 constant DESTINATION_DOMAIN = 1_918_988_905; // Rari

    function setUp() public {
        // Deploy mailbox
        mailbox = new MockMailbox();

        // Deploy ChainBalanceManager with mailbox
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy beaconProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainBalanceManager()),
            owner,
            abi.encodeWithSignature("initialize(address,address,uint32,address)", owner, address(mailbox), DESTINATION_DOMAIN, address(0x999))
        );

        chainBalanceManager = ChainBalanceManager(address(beaconProxy));

        // Deploy mocks
        usdc = new MockUSDC();
        lendingPool = new MockLendingPool();

        // Deploy VaultFactory
        vaultFactory = new VaultFactory(address(chainBalanceManager));

        // Setup tokens
        usdc.mint(user1, initialBalance);

        // Whitelist token
        vm.prank(owner);
        chainBalanceManager.addToken(address(usdc));

        // Set token mapping (required for deposit)
        vm.prank(owner);
        chainBalanceManager.setTokenMapping(address(usdc), address(usdc));
    }

    function test_SetVaultFactory() public {
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        assertEq(chainBalanceManager.getVaultFactory(), address(vaultFactory));
    }

    function test_SetVaultFactoryRevertIfNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.setVaultFactory(address(vaultFactory));
    }

    function test_SetVaultFactoryRevertIfZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IChainBalanceManagerErrors.ZeroAddress.selector);
        chainBalanceManager.setVaultFactory(address(0));
    }

    function test_CreateVault() public {
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        address vault = chainBalanceManager.getVault(address(usdc));
        assertTrue(vault != address(0));

        // Verify vault properties
        Vault vaultContract = Vault(vault);
        assertEq(vaultContract.asset(), address(usdc));
        assertEq(vaultContract.chainBalanceManager(), address(chainBalanceManager));
    }

    function test_CreateVaultRevertIfNotOwner() public {
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.createVault(address(usdc), address(lendingPool));
    }

    function test_SetAllocationSettings() public {
        uint256 keepBps = 2000; // 20%
        uint256 vaultBps = 8000; // 80%

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), keepBps, vaultBps);

        (uint256 returnedKeepBps, uint256 returnedVaultBps) =
            chainBalanceManager.getAllocationSettings(address(usdc));

        assertEq(returnedKeepBps, keepBps);
        assertEq(returnedVaultBps, vaultBps);
    }

    function test_SetAllocationSettingsRevertIfNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000);
    }

    function test_SetAllocationSettingsRevertIfNotSum10000() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.InvalidAllocation.selector, 2000, 7000));
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 7000); // Only 90%
    }

    function test_SetDefaultAllocation() public {
        uint256 keepBps = 3000; // 30%
        uint256 vaultBps = 7000; // 70%

        vm.prank(owner);
        chainBalanceManager.setDefaultAllocation(keepBps, vaultBps);

        // Should use default allocation for tokens without specific settings
        (uint256 returnedKeepBps, uint256 returnedVaultBps) =
            chainBalanceManager.getAllocationSettings(address(usdc));

        assertEq(returnedKeepBps, keepBps);
        assertEq(returnedVaultBps, vaultBps);
    }

    function test_SetDefaultAllocationRevertIfNotSum10000() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.InvalidAllocation.selector, 3000, 6000));
        chainBalanceManager.setDefaultAllocation(3000, 6000); // Only 90%
    }

    function test_RebalanceDepositsToVault() public {
        uint256 depositAmount = 1_000_000e6; // 1M USDC

        // Setup
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000); // 20% keep, 80% vault

        // Deposit tokens
        vm.prank(user1);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.prank(user1);
        chainBalanceManager.deposit(address(usdc), depositAmount, user1);

        // Rebalance
        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        address vault = chainBalanceManager.getVault(address(usdc));

        // Check balances
        uint256 expectedKeep = (depositAmount * 2000) / 10000; // 20%
        uint256 expectedVault = (depositAmount * 8000) / 10000; // 80%

        assertEq(usdc.balanceOf(address(chainBalanceManager)), expectedKeep);
        assertEq(Vault(vault).totalAssets(), expectedVault);
    }

    function test_RebalanceWithdrawsFromVault() public {
        uint256 depositAmount = 1_000_000e6; // 1M USDC

        // Setup and initial deposit
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000);

        vm.prank(user1);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.prank(user1);
        chainBalanceManager.deposit(address(usdc), depositAmount, user1);

        // Initial rebalance
        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        address vault = chainBalanceManager.getVault(address(usdc));
        uint256 vaultBalanceAfterFirstRebalance = Vault(vault).totalAssets();

        // Verify vault has funds
        assertGt(vaultBalanceAfterFirstRebalance, 0);

        // Withdraw all from vault back to ChainBalanceManager
        vm.prank(owner);
        chainBalanceManager.withdrawAllFromVault(address(usdc));

        // Verify vault is now empty
        assertEq(Vault(vault).totalAssets(), 0);

        // Rebalance again - should deposit to vault to maintain ratio
        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        // Vault should have funds again after rebalancing
        assertGt(Vault(vault).totalAssets(), 0);
        assertApproxEqRel(Vault(vault).totalAssets(), vaultBalanceAfterFirstRebalance, 0.01e18); // Should be ~same as before
    }

    function test_RebalanceRevertIfNotOwner() public {
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.rebalance(address(usdc));
    }

    function test_RebalanceRevertIfVaultNotFound() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.VaultNotFound.selector, address(usdc)));
        chainBalanceManager.rebalance(address(usdc));
    }

    function test_RebalanceWithYieldGeneration() public {
        uint256 depositAmount = 1_000_000e6; // 1M USDC

        // Setup
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000);

        // Deposit and rebalance
        vm.prank(user1);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.prank(user1);
        chainBalanceManager.deposit(address(usdc), depositAmount, user1);

        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        address vault = chainBalanceManager.getVault(address(usdc));

        // Deposit vault funds to yield protocol
        uint256 vaultBalance = Vault(vault).totalAssets();
        vm.prank(address(chainBalanceManager));
        Vault(vault).depositToYieldProtocol(vaultBalance);

        // Fast forward time to generate yield
        vm.warp(block.timestamp + 365 days);

        // Accrue yield
        lendingPool.accrueYield(address(usdc), vault);

        // Check that yield was generated
        uint256 balanceInPool = lendingPool.balanceOf(address(usdc), vault);
        assertGt(balanceInPool, vaultBalance);
    }

    function test_MultipleTokenVaults() public {
        MockUSDC weth = new MockUSDC(); // Using MockUSDC as a second token
        weth.mint(user1, initialBalance);

        // Setup both tokens
        vm.prank(owner);
        chainBalanceManager.addToken(address(weth));

        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.createVault(address(weth), address(lendingPool));

        // Different allocations
        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000);

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(weth), 3000, 7000);

        // Verify vaults exist
        assertTrue(chainBalanceManager.getVault(address(usdc)) != address(0));
        assertTrue(chainBalanceManager.getVault(address(weth)) != address(0));
        assertTrue(chainBalanceManager.getVault(address(usdc)) != chainBalanceManager.getVault(address(weth)));

        // Verify allocations
        (uint256 usdcKeep, uint256 usdcVault) = chainBalanceManager.getAllocationSettings(address(usdc));
        assertEq(usdcKeep, 2000);
        assertEq(usdcVault, 8000);

        (uint256 wethKeep, uint256 wethVault) = chainBalanceManager.getAllocationSettings(address(weth));
        assertEq(wethKeep, 3000);
        assertEq(wethVault, 7000);
    }

    function test_RebalanceEmitsEvent() public {
        uint256 depositAmount = 1_000_000e6;

        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000);

        vm.prank(user1);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.prank(user1);
        chainBalanceManager.deposit(address(usdc), depositAmount, user1);

        uint256 expectedKeep = (depositAmount * 2000) / 10000;
        uint256 expectedVault = (depositAmount * 8000) / 10000;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ChainBalanceManager.Rebalanced(address(usdc), expectedKeep, expectedVault);

        chainBalanceManager.rebalance(address(usdc));
    }

    function test_GetVaultReturnsZeroIfNotCreated() public {
        assertEq(chainBalanceManager.getVault(address(usdc)), address(0));
    }

    function test_WithdrawAllFromVault() public {
        uint256 depositAmount = 1_000_000e6; // 1M USDC

        // Setup
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000); // 20% keep, 80% vault

        // Deposit tokens
        vm.prank(user1);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.prank(user1);
        chainBalanceManager.deposit(address(usdc), depositAmount, user1);

        // Rebalance to move funds to vault
        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        address vault = chainBalanceManager.getVault(address(usdc));
        uint256 vaultBalanceBefore = Vault(vault).totalAssets();
        uint256 managerBalanceBefore = usdc.balanceOf(address(chainBalanceManager));

        assertGt(vaultBalanceBefore, 0); // Vault should have funds

        // Withdraw all from vault
        vm.prank(owner);
        chainBalanceManager.withdrawAllFromVault(address(usdc));

        // Check balances after withdrawal
        assertEq(Vault(vault).totalAssets(), 0); // Vault should be empty
        assertEq(usdc.balanceOf(address(chainBalanceManager)), managerBalanceBefore + vaultBalanceBefore); // Manager should have all funds
    }

    function test_WithdrawAllFromVaultRevertIfNotOwner() public {
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(notOwner);
        vm.expectRevert();
        chainBalanceManager.withdrawAllFromVault(address(usdc));
    }

    function test_WithdrawAllFromVaultRevertIfVaultNotFound() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IChainBalanceManagerErrors.VaultNotFound.selector, address(usdc)));
        chainBalanceManager.withdrawAllFromVault(address(usdc));
    }

    function test_WithdrawAllFromVaultRevertIfZeroBalance() public {
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        vm.expectRevert(IChainBalanceManagerErrors.ZeroAmount.selector);
        chainBalanceManager.withdrawAllFromVault(address(usdc));
    }

    function test_CompleteFlowDepositRebalanceWithdraw() public {
        uint256 depositAmount = 1_000_000e6;

        // 1. Setup
        vm.prank(owner);
        chainBalanceManager.setVaultFactory(address(vaultFactory));

        vm.prank(owner);
        chainBalanceManager.createVault(address(usdc), address(lendingPool));

        vm.prank(owner);
        chainBalanceManager.setAllocationSettings(address(usdc), 2000, 8000);

        // 2. User deposits
        vm.prank(user1);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.prank(user1);
        chainBalanceManager.deposit(address(usdc), depositAmount, user1);

        // 3. Owner rebalances
        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        address vault = chainBalanceManager.getVault(address(usdc));

        uint256 expectedKeep = (depositAmount * 2000) / 10000;
        uint256 expectedVault = (depositAmount * 8000) / 10000;

        assertEq(usdc.balanceOf(address(chainBalanceManager)), expectedKeep);
        assertEq(Vault(vault).totalAssets(), expectedVault);

        // 4. Test emergency withdrawal from vault
        uint256 managerBalanceBefore = usdc.balanceOf(address(chainBalanceManager));
        uint256 vaultBalanceBefore = Vault(vault).totalAssets();

        vm.prank(owner);
        chainBalanceManager.withdrawAllFromVault(address(usdc));

        // Verify all funds moved from vault to manager
        assertEq(Vault(vault).totalAssets(), 0);
        assertEq(usdc.balanceOf(address(chainBalanceManager)), managerBalanceBefore + vaultBalanceBefore);

        // 5. Rebalance again to restore allocation
        vm.prank(owner);
        chainBalanceManager.rebalance(address(usdc));

        // ChainBalanceManager should maintain the 20/80 ratio
        assertApproxEqRel(
            usdc.balanceOf(address(chainBalanceManager)),
            expectedKeep,
            0.01e18 // 1% tolerance
        );

        assertApproxEqRel(
            Vault(vault).totalAssets(),
            expectedVault,
            0.01e18 // 1% tolerance
        );
    }
}
