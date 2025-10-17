// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import "../../src/vaults/VaultFactory.sol";
import "../../src/vaults/Vault.sol";
import "../../src/vaults/interfaces/IVaultFactory.sol";
import "../../src/mocks/MockLendingPool.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockWETH.sol";

contract VaultFactoryTest is Test {
    VaultFactory private factory;
    MockLendingPool private lendingPool;
    MockUSDC private usdc;
    MockWETH private weth;

    address private chainBalanceManager = address(0x123);
    address private notOwner = address(0x456);

    function setUp() public {
        // Deploy mock tokens and lending pool
        usdc = new MockUSDC();
        weth = new MockWETH();
        lendingPool = new MockLendingPool();

        // Deploy factory with chainBalanceManager as owner
        factory = new VaultFactory(chainBalanceManager);
    }

    function test_Initialize() public {
        assertEq(factory.owner(), chainBalanceManager);
        assertEq(factory.chainBalanceManager(), chainBalanceManager);
        assertEq(factory.vaultCount(), 0);
    }

    function test_CreateVault() public {
        vm.prank(chainBalanceManager);
        address vault = factory.createVault(address(usdc), address(lendingPool));

        assertTrue(vault != address(0));
        assertEq(factory.getVault(address(usdc)), vault);
        assertTrue(factory.vaultExists(address(usdc)));
        assertEq(factory.vaultCount(), 1);

        // Verify vault properties
        Vault vaultContract = Vault(vault);
        assertEq(vaultContract.asset(), address(usdc));
        assertEq(vaultContract.chainBalanceManager(), chainBalanceManager);
        assertEq(vaultContract.lendingPool(), address(lendingPool));
    }

    function test_CreateVaultRevertIfNotOwner() public {
        vm.prank(notOwner);
        vm.expectRevert();
        factory.createVault(address(usdc), address(lendingPool));
    }

    function test_CreateVaultRevertIfZeroAsset() public {
        vm.prank(chainBalanceManager);
        vm.expectRevert(IVaultFactory.ZeroAddress.selector);
        factory.createVault(address(0), address(lendingPool));
    }

    function test_CreateVaultRevertIfZeroLendingPool() public {
        vm.prank(chainBalanceManager);
        vm.expectRevert(IVaultFactory.ZeroAddress.selector);
        factory.createVault(address(usdc), address(0));
    }

    function test_CreateVaultRevertIfAlreadyExists() public {
        vm.prank(chainBalanceManager);
        factory.createVault(address(usdc), address(lendingPool));

        vm.prank(chainBalanceManager);
        vm.expectRevert(IVaultFactory.VaultAlreadyExists.selector);
        factory.createVault(address(usdc), address(lendingPool));
    }

    function test_CreateMultipleVaults() public {
        // Create USDC vault
        vm.prank(chainBalanceManager);
        address usdcVault = factory.createVault(address(usdc), address(lendingPool));

        // Create WETH vault
        vm.prank(chainBalanceManager);
        address wethVault = factory.createVault(address(weth), address(lendingPool));

        assertEq(factory.vaultCount(), 2);
        assertEq(factory.getVault(address(usdc)), usdcVault);
        assertEq(factory.getVault(address(weth)), wethVault);
        assertTrue(factory.vaultExists(address(usdc)));
        assertTrue(factory.vaultExists(address(weth)));
    }

    function test_GetAllVaults() public {
        // Initially empty
        address[] memory vaults = factory.getAllVaults();
        assertEq(vaults.length, 0);

        // Create first vault
        vm.prank(chainBalanceManager);
        address usdcVault = factory.createVault(address(usdc), address(lendingPool));

        vaults = factory.getAllVaults();
        assertEq(vaults.length, 1);
        assertEq(vaults[0], usdcVault);

        // Create second vault
        vm.prank(chainBalanceManager);
        address wethVault = factory.createVault(address(weth), address(lendingPool));

        vaults = factory.getAllVaults();
        assertEq(vaults.length, 2);
        assertEq(vaults[0], usdcVault);
        assertEq(vaults[1], wethVault);
    }

    function test_VaultExists() public {
        assertFalse(factory.vaultExists(address(usdc)));

        vm.prank(chainBalanceManager);
        factory.createVault(address(usdc), address(lendingPool));

        assertTrue(factory.vaultExists(address(usdc)));
        assertFalse(factory.vaultExists(address(weth)));
    }

    function test_GetVaultReturnsZeroIfNotExists() public {
        assertEq(factory.getVault(address(usdc)), address(0));

        vm.prank(chainBalanceManager);
        address vault = factory.createVault(address(usdc), address(lendingPool));

        assertEq(factory.getVault(address(usdc)), vault);
        assertEq(factory.getVault(address(weth)), address(0));
    }

    function test_VaultCountIncreases() public {
        assertEq(factory.vaultCount(), 0);

        vm.prank(chainBalanceManager);
        factory.createVault(address(usdc), address(lendingPool));
        assertEq(factory.vaultCount(), 1);

        vm.prank(chainBalanceManager);
        factory.createVault(address(weth), address(lendingPool));
        assertEq(factory.vaultCount(), 2);
    }
}
