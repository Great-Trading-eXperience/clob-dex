// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@gtx/mocks/MockUSDC.sol";
import "@gtx/mocks/MockWETH.sol";
import "@gtx/mocks/MockERC4626Vault.sol";
import "../../src/mocks/MockMailbox.sol";
import "../../src/core/ChainBalanceManager.sol";
import "../../src/core/interfaces/IChainBalanceManagerErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {MerkleTree} from "./helpers/MerkleTree.sol";

/**
 * @title ChainBalanceManagerYieldTest
 * @dev Comprehensive tests for the yield distribution system
 * Tests: vault integration, Merkle snapshots, yield claiming, fairness model
 */
contract ChainBalanceManagerYieldTest is Test {
    ChainBalanceManager private chainBalanceManager;
    address private owner = address(0x123);
    address private alice = address(0x456);
    address private bob = address(0x789);
    address private charlie = address(0xABC);

    MockUSDC private usdc;
    MockWETH private weth;
    MockERC4626Vault private usdcVault;
    MockERC4626Vault private wethVault;
    MockMailbox private mailbox;

    uint256 private constant INITIAL_BALANCE = 1000 ether;
    uint256 private constant INITIAL_USDC = 1_000_000e6; // 1M USDC

    event VaultSet(address indexed token, address indexed vault);
    event VaultDeposit(address indexed token, address indexed vault, uint256 amount, uint256 shares);
    event TokenSnapshotUpdated(uint256 indexed day, address indexed token, bytes32 merkleRoot, uint256 totalSupply);
    event YieldClaimed(address indexed user, address indexed token, uint256 amount, uint256 day);

    function setUp() public {
        // Deploy mock mailbox for cross-chain messaging
        mailbox = new MockMailbox();

        // Deploy ChainBalanceManager with mock mailbox
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy beaconProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainBalanceManager()),
            owner,
            abi.encodeWithSignature(
                "initialize(address,address,uint32,address)",
                owner,
                address(mailbox),  // Use mock mailbox
                1,                 // destination domain
                address(0x999)     // mock destination balance manager
            )
        );

        chainBalanceManager = ChainBalanceManager(address(beaconProxy));

        // Deploy mock tokens
        usdc = new MockUSDC();
        weth = new MockWETH();

        // Deploy mock vaults as owner (so owner can call addYield)
        vm.startPrank(owner);
        usdcVault = new MockERC4626Vault(IERC20(address(usdc)), "Vault USDC", "vUSDC");
        wethVault = new MockERC4626Vault(IERC20(address(weth)), "Vault WETH", "vWETH");
        vm.stopPrank();

        // Mint tokens to users
        usdc.mint(alice, INITIAL_USDC);
        usdc.mint(bob, INITIAL_USDC);
        usdc.mint(charlie, INITIAL_USDC);
        usdc.mint(owner, INITIAL_USDC * 10); // Extra for adding yield

        weth.mint(alice, INITIAL_BALANCE);
        weth.mint(bob, INITIAL_BALANCE);
        weth.mint(charlie, INITIAL_BALANCE);
        weth.mint(owner, INITIAL_BALANCE * 10); // Extra for adding yield

        // Give ETH to users
        vm.deal(alice, INITIAL_BALANCE);
        vm.deal(bob, INITIAL_BALANCE);
        vm.deal(charlie, INITIAL_BALANCE);
        vm.deal(owner, INITIAL_BALANCE);

        // Whitelist tokens and set up token mappings
        vm.startPrank(owner);
        chainBalanceManager.addToken(address(usdc));
        chainBalanceManager.addToken(address(weth));

        // Set token mappings (for testing, map to themselves as synthetic tokens)
        chainBalanceManager.setTokenMapping(address(usdc), address(usdc));
        chainBalanceManager.setTokenMapping(address(weth), address(weth));
        vm.stopPrank();
    }

    // =============================================================
    //                  VAULT INTEGRATION TESTS
    // =============================================================

    function test_SetVault() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit VaultSet(address(usdc), address(usdcVault));
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        assertEq(chainBalanceManager.getVault(address(usdc)), address(usdcVault));
    }

    function test_SetVaultRevertIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        chainBalanceManager.setVault(address(usdc), address(usdcVault));
    }

    function test_SetVaultRatio() public {
        vm.prank(owner);
        chainBalanceManager.setVaultRatio(9000); // 90%

        assertEq(chainBalanceManager.getVaultRatio(), 9000);
    }

    function test_SetVaultRatioRevertIfExceeds100Percent() public {
        vm.prank(owner);
        vm.expectRevert();
        chainBalanceManager.setVaultRatio(10001); // > 100%
    }

    function test_DepositWithVaultIntegration() public {
        uint256 depositAmount = 1000e6; // 1000 USDC
        uint256 expectedVaultAmount = (depositAmount * 8000) / 10000; // 80%
        uint256 expectedHotReserve = depositAmount - expectedVaultAmount; // 20%

        // Set up vault
        vm.prank(owner);
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        // Deposit
        vm.startPrank(alice);
        usdc.approve(address(chainBalanceManager), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit VaultDeposit(address(usdc), address(usdcVault), expectedVaultAmount, expectedVaultAmount);

        chainBalanceManager.deposit(address(usdc), depositAmount, alice);
        vm.stopPrank();

        // Verify vault received 80%
        assertEq(usdcVault.totalAssets(), expectedVaultAmount);

        // Verify vault shares tracked
        assertEq(chainBalanceManager.getVaultShares(address(usdc)), expectedVaultAmount);

        // Verify total deposited is tracked
        (uint256 totalDeposited,,) = chainBalanceManager.getTokenStats(address(usdc));
        assertEq(totalDeposited, depositAmount);
    }

    function test_DepositWithoutVault() public {
        uint256 depositAmount = 1000e6;

        // No vault configured - should deposit normally
        vm.startPrank(alice);
        usdc.approve(address(chainBalanceManager), depositAmount);
        chainBalanceManager.deposit(address(usdc), depositAmount, alice);
        vm.stopPrank();

        // Verify all tokens in ChainBalanceManager (not in vault)
        assertEq(usdc.balanceOf(address(chainBalanceManager)), depositAmount);
        assertEq(usdcVault.totalAssets(), 0);
    }

    function test_DepositWithCustomVaultRatio() public {
        uint256 depositAmount = 1000e6;
        uint256 customRatio = 9000; // 90%
        uint256 expectedVaultAmount = (depositAmount * customRatio) / 10000;

        // Set custom vault ratio
        vm.prank(owner);
        chainBalanceManager.setVaultRatio(customRatio);

        // Set up vault
        vm.prank(owner);
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        // Deposit
        vm.startPrank(alice);
        usdc.approve(address(chainBalanceManager), depositAmount);
        chainBalanceManager.deposit(address(usdc), depositAmount, alice);
        vm.stopPrank();

        // Verify 90% went to vault
        assertEq(usdcVault.totalAssets(), expectedVaultAmount);
    }

    // =============================================================
    //                  MERKLE SNAPSHOT TESTS
    // =============================================================

    function test_UpdateDailySnapshot() public {
        uint256 day = 1;
        bytes32 usdcRoot = bytes32(uint256(0x123));
        bytes32 wethRoot = bytes32(uint256(0x456));

        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](2);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: usdcRoot,
            totalSupply: 10000e6,
            cumulativeYield: 100e6
        });
        snapshots[1] = ChainBalanceManager.TokenSnapshot({
            token: address(weth),
            merkleRoot: wethRoot,
            totalSupply: 100 ether,
            cumulativeYield: 2 ether
        });

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit TokenSnapshotUpdated(day, address(usdc), usdcRoot, 10000e6);
        chainBalanceManager.updateDailySnapshot(day, snapshots);

        // Verify snapshot data
        (bytes32 root, uint256 supply, uint256 yield) = chainBalanceManager.getSnapshot(day, address(usdc));
        assertEq(root, usdcRoot);
        assertEq(supply, 10000e6);
        assertEq(yield, 100e6);

        // Verify snapshot tokens list
        address[] memory tokens = chainBalanceManager.getSnapshotTokens(day);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(usdc));
        assertEq(tokens[1], address(weth));

        // Verify latest snapshot day
        assertEq(chainBalanceManager.getLatestSnapshotDay(), day);
    }

    function test_UpdateSnapshotRevertIfNotOwner() public {
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: bytes32(uint256(0x123)),
            totalSupply: 10000e6,
            cumulativeYield: 100e6
        });

        vm.prank(alice);
        vm.expectRevert();
        chainBalanceManager.updateDailySnapshot(1, snapshots);
    }

    function test_UpdateSnapshotMultipleDays() public {
        // Day 1 snapshot
        ChainBalanceManager.TokenSnapshot[] memory snapshots1 = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots1[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: bytes32(uint256(0x111)),
            totalSupply: 10000e6,
            cumulativeYield: 100e6
        });

        vm.prank(owner);
        chainBalanceManager.updateDailySnapshot(1, snapshots1);

        // Day 2 snapshot (more yield)
        ChainBalanceManager.TokenSnapshot[] memory snapshots2 = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots2[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: bytes32(uint256(0x222)),
            totalSupply: 10000e6,
            cumulativeYield: 220e6 // More cumulative yield
        });

        vm.prank(owner);
        chainBalanceManager.updateDailySnapshot(2, snapshots2);

        // Verify both snapshots exist
        (, , uint256 yield1) = chainBalanceManager.getSnapshot(1, address(usdc));
        (, , uint256 yield2) = chainBalanceManager.getSnapshot(2, address(usdc));

        assertEq(yield1, 100e6);
        assertEq(yield2, 220e6);
        assertEq(chainBalanceManager.getLatestSnapshotDay(), 2);
    }

    // =============================================================
    //                  YIELD CLAIMING TESTS
    // =============================================================

    function test_ClaimYieldWithValidProof() public {
        uint256 day = 1;
        uint256 aliceBalance = 3000e6; // Alice holds 30% of supply
        uint256 totalSupply = 10000e6;
        uint256 totalYield = 100e6;
        uint256 expectedYield = (totalYield * aliceBalance) / totalSupply; // 30e6

        // Build Merkle tree
        MerkleTree merkleTree = new MerkleTree();
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = keccak256(abi.encodePacked(alice, aliceBalance));
        leaves[1] = keccak256(abi.encodePacked(bob, uint256(5000e6)));
        leaves[2] = keccak256(abi.encodePacked(charlie, uint256(2000e6)));

        bytes32 root = merkleTree.getRoot(leaves);
        bytes32[] memory proof = merkleTree.getProof(leaves, 0);

        // Set up vault and add yield
        vm.startPrank(owner);
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        // First deposit to vault so ChainBalanceManager has shares
        usdc.approve(address(usdcVault), totalSupply);
        usdcVault.deposit(totalSupply, address(chainBalanceManager));

        // Then add yield on top
        usdc.approve(address(usdcVault), totalYield);
        usdcVault.addYield(totalYield);
        vm.stopPrank();

        // Post snapshot
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: root,
            totalSupply: totalSupply,
            cumulativeYield: totalYield
        });

        vm.prank(owner);
        chainBalanceManager.updateDailySnapshot(day, snapshots);

        // Claim yield
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit YieldClaimed(alice, address(usdc), expectedYield, day);
        chainBalanceManager.claimYield(day, address(usdc), aliceBalance, proof);

        uint256 aliceBalanceAfter = usdc.balanceOf(alice);

        // Verify yield received
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedYield);
        assertEq(chainBalanceManager.getUserClaimedYield(alice, address(usdc)), expectedYield);
    }

    function test_ClaimYieldRevertInvalidProof() public {
        uint256 day = 1;
        uint256 aliceBalance = 3000e6;

        // Build Merkle tree
        MerkleTree merkleTree = new MerkleTree();
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(bob, uint256(5000e6))); // Alice not in tree
        leaves[1] = keccak256(abi.encodePacked(charlie, uint256(2000e6)));

        bytes32 root = merkleTree.getRoot(leaves);
        bytes32[] memory proof = merkleTree.getProof(leaves, 0); // Wrong proof

        // Post snapshot
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: root,
            totalSupply: 10000e6,
            cumulativeYield: 100e6
        });

        vm.prank(owner);
        chainBalanceManager.updateDailySnapshot(day, snapshots);

        // Try to claim with invalid proof
        vm.prank(alice);
        vm.expectRevert("Invalid Merkle proof");
        chainBalanceManager.claimYield(day, address(usdc), aliceBalance, proof);
    }

    function test_ClaimYieldRevertIfAlreadyClaimed() public {
        uint256 day = 1;
        uint256 aliceBalance = 3000e6;
        uint256 totalSupply = 10000e6;
        uint256 totalYield = 100e6;

        // Build Merkle tree
        MerkleTree merkleTree = new MerkleTree();
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256(abi.encodePacked(alice, aliceBalance));

        bytes32 root = merkleTree.getRoot(leaves);
        bytes32[] memory proof = merkleTree.getProof(leaves, 0);

        // Set up vault and add yield
        vm.startPrank(owner);
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        // First deposit to vault so ChainBalanceManager has shares
        usdc.approve(address(usdcVault), totalSupply);
        usdcVault.deposit(totalSupply, address(chainBalanceManager));

        // Then add yield on top
        usdc.approve(address(usdcVault), totalYield);
        usdcVault.addYield(totalYield);

        // Post snapshot
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: root,
            totalSupply: totalSupply,
            cumulativeYield: totalYield
        });
        chainBalanceManager.updateDailySnapshot(day, snapshots);
        vm.stopPrank();

        // First claim - should succeed
        vm.prank(alice);
        chainBalanceManager.claimYield(day, address(usdc), aliceBalance, proof);

        // Second claim - should revert
        vm.prank(alice);
        vm.expectRevert("Yield already claimed");
        chainBalanceManager.claimYield(day, address(usdc), aliceBalance, proof);
    }

    function test_ClaimYieldBatch() public {
        uint256 day = 1;
        uint256 aliceUSDC = 3000e6;
        uint256 aliceWETH = 30 ether;
        uint256 usdcSupply = 10000e6;
        uint256 wethSupply = 100 ether;
        uint256 usdcYield = 100e6;
        uint256 wethYield = 2 ether;

        // Build USDC tree
        MerkleTree usdcTree = new MerkleTree();
        bytes32[] memory usdcLeaves = new bytes32[](1);
        usdcLeaves[0] = keccak256(abi.encodePacked(alice, aliceUSDC));
        bytes32 usdcRoot = usdcTree.getRoot(usdcLeaves);
        bytes32[] memory usdcProof = usdcTree.getProof(usdcLeaves, 0);

        // Build WETH tree
        MerkleTree wethTree = new MerkleTree();
        bytes32[] memory wethLeaves = new bytes32[](1);
        wethLeaves[0] = keccak256(abi.encodePacked(alice, aliceWETH));
        bytes32 wethRoot = wethTree.getRoot(wethLeaves);
        bytes32[] memory wethProof = wethTree.getProof(wethLeaves, 0);

        // Set up vaults and add yield
        vm.startPrank(owner);
        chainBalanceManager.setVault(address(usdc), address(usdcVault));
        chainBalanceManager.setVault(address(weth), address(wethVault));

        // First deposit to vaults so ChainBalanceManager has shares
        usdc.approve(address(usdcVault), usdcSupply);
        usdcVault.deposit(usdcSupply, address(chainBalanceManager));

        weth.approve(address(wethVault), wethSupply);
        wethVault.deposit(wethSupply, address(chainBalanceManager));

        // Then add yield on top
        usdc.approve(address(usdcVault), usdcYield);
        usdcVault.addYield(usdcYield);

        weth.approve(address(wethVault), wethYield);
        wethVault.addYield(wethYield);

        // Post snapshots
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](2);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: usdcRoot,
            totalSupply: usdcSupply,
            cumulativeYield: usdcYield
        });
        snapshots[1] = ChainBalanceManager.TokenSnapshot({
            token: address(weth),
            merkleRoot: wethRoot,
            totalSupply: wethSupply,
            cumulativeYield: wethYield
        });
        chainBalanceManager.updateDailySnapshot(day, snapshots);
        vm.stopPrank();

        // Claim batch
        ChainBalanceManager.ClaimProof[] memory proofs = new ChainBalanceManager.ClaimProof[](2);
        proofs[0] = ChainBalanceManager.ClaimProof({
            token: address(usdc),
            userBalance: aliceUSDC,
            merkleProof: usdcProof
        });
        proofs[1] = ChainBalanceManager.ClaimProof({
            token: address(weth),
            userBalance: aliceWETH,
            merkleProof: wethProof
        });

        uint256 usdcBefore = usdc.balanceOf(alice);
        uint256 wethBefore = weth.balanceOf(alice);

        vm.prank(alice);
        chainBalanceManager.claimYieldBatch(day, proofs);

        uint256 usdcAfter = usdc.balanceOf(alice);
        uint256 wethAfter = weth.balanceOf(alice);

        // Verify both yields claimed
        uint256 expectedUSDCYield = (usdcYield * aliceUSDC) / usdcSupply;
        uint256 expectedWETHYield = (wethYield * aliceWETH) / wethSupply;

        assertEq(usdcAfter - usdcBefore, expectedUSDCYield);
        assertEq(wethAfter - wethBefore, expectedWETHYield);
    }

    // =============================================================
    //                  FAIRNESS MODEL TESTS
    // =============================================================

    function test_FairnessModel_TradeAwayLoseYield() public {
        /**
         * Scenario: Bob deposits 1 BTC but trades it away
         * Fair: Bob should NOT get BTC yield (he doesn't hold BTC anymore)
         *
         * Day 0: Bob deposits 1 WETH
         * Day 100: Bob trades WETH → USDC (simulated by different balances)
         * Day 365: Yield distribution → Bob gets USDC yield, NOT WETH yield
         */
        uint256 day = 365;

        // Bob's holdings on Day 365: 0 WETH, 100,000 USDC (traded away WETH)
        uint256 bobWETH = 0;
        uint256 bobUSDC = 100_000e6;

        // Build trees
        MerkleTree wethTree = new MerkleTree();
        bytes32[] memory wethLeaves = new bytes32[](1);
        wethLeaves[0] = keccak256(abi.encodePacked(alice, uint256(100 ether))); // Alice holds all WETH
        bytes32 wethRoot = wethTree.getRoot(wethLeaves);

        MerkleTree usdcTree = new MerkleTree();
        bytes32[] memory usdcLeaves = new bytes32[](1);
        usdcLeaves[0] = keccak256(abi.encodePacked(bob, bobUSDC)); // Bob holds USDC
        bytes32 usdcRoot = usdcTree.getRoot(usdcLeaves);
        bytes32[] memory usdcProof = usdcTree.getProof(usdcLeaves, 0);

        // Set up vaults
        vm.startPrank(owner);
        chainBalanceManager.setVault(address(weth), address(wethVault));
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        // First deposit to vaults so ChainBalanceManager has shares
        weth.approve(address(wethVault), 100 ether);
        wethVault.deposit(100 ether, address(chainBalanceManager));

        usdc.approve(address(usdcVault), 100_000e6);
        usdcVault.deposit(100_000e6, address(chainBalanceManager));

        // Add yield to both vaults
        weth.approve(address(wethVault), 2 ether);
        wethVault.addYield(2 ether);

        usdc.approve(address(usdcVault), 6000e6);
        usdcVault.addYield(6000e6);

        // Post snapshots
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](2);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(weth),
            merkleRoot: wethRoot,
            totalSupply: 100 ether,
            cumulativeYield: 2 ether
        });
        snapshots[1] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: usdcRoot,
            totalSupply: 100_000e6,
            cumulativeYield: 6000e6
        });
        chainBalanceManager.updateDailySnapshot(day, snapshots);
        vm.stopPrank();

        // Bob tries to claim WETH yield - should get 0 (no balance)
        uint256 claimable = chainBalanceManager.calculateClaimableYield(day, address(weth), bobWETH);
        assertEq(claimable, 0, "Bob should NOT get WETH yield after trading away");

        // Bob claims USDC yield - should succeed (he holds USDC)
        uint256 bobUSDCBefore = usdc.balanceOf(bob);

        vm.prank(bob);
        chainBalanceManager.claimYield(day, address(usdc), bobUSDC, usdcProof);

        uint256 bobUSDCAfter = usdc.balanceOf(bob);
        uint256 expectedUSDCYield = (6000e6 * bobUSDC) / 100_000e6;

        assertEq(bobUSDCAfter - bobUSDCBefore, expectedUSDCYield, "Bob should get USDC yield");
    }

    function test_FairnessModel_ProportionalDistribution() public {
        /**
         * Multiple users holding different amounts
         * Yield should be distributed proportionally
         */
        uint256 day = 1;
        uint256 aliceBalance = 3000e6; // 30%
        uint256 bobBalance = 5000e6;   // 50%
        uint256 charlieBalance = 2000e6; // 20%
        uint256 totalSupply = 10000e6;
        uint256 totalYield = 1000e6;

        // Build tree
        MerkleTree merkleTree = new MerkleTree();
        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = keccak256(abi.encodePacked(alice, aliceBalance));
        leaves[1] = keccak256(abi.encodePacked(bob, bobBalance));
        leaves[2] = keccak256(abi.encodePacked(charlie, charlieBalance));

        bytes32 root = merkleTree.getRoot(leaves);

        // Pre-generate all proofs (must be done before any state changes)
        bytes32[] memory aliceProof = merkleTree.getProof(leaves, 0);
        bytes32[] memory bobProof = merkleTree.getProof(leaves, 1);
        bytes32[] memory charlieProof = merkleTree.getProof(leaves, 2);

        // Set up vault
        vm.startPrank(owner);
        chainBalanceManager.setVault(address(usdc), address(usdcVault));

        // First deposit to vault so ChainBalanceManager has shares
        usdc.approve(address(usdcVault), totalSupply);
        usdcVault.deposit(totalSupply, address(chainBalanceManager));

        // Then add yield on top
        usdc.approve(address(usdcVault), totalYield);
        usdcVault.addYield(totalYield);

        // Post snapshot
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: root,
            totalSupply: totalSupply,
            cumulativeYield: totalYield
        });
        chainBalanceManager.updateDailySnapshot(day, snapshots);
        vm.stopPrank();

        // Each user claims
        vm.prank(alice);
        chainBalanceManager.claimYield(day, address(usdc), aliceBalance, aliceProof);

        vm.prank(bob);
        chainBalanceManager.claimYield(day, address(usdc), bobBalance, bobProof);

        vm.prank(charlie);
        chainBalanceManager.claimYield(day, address(usdc), charlieBalance, charlieProof);

        // Verify proportional distribution
        uint256 aliceYield = chainBalanceManager.getUserClaimedYield(alice, address(usdc));
        uint256 bobYield = chainBalanceManager.getUserClaimedYield(bob, address(usdc));
        uint256 charlieYield = chainBalanceManager.getUserClaimedYield(charlie, address(usdc));

        assertEq(aliceYield, (totalYield * 30) / 100, "Alice should get 30%");
        assertEq(bobYield, (totalYield * 50) / 100, "Bob should get 50%");
        assertEq(charlieYield, (totalYield * 20) / 100, "Charlie should get 20%");

        // Total should equal 100%
        assertEq(aliceYield + bobYield + charlieYield, totalYield, "All yield should be distributed");
    }

    // =============================================================
    //                  VIEW FUNCTION TESTS
    // =============================================================

    function test_CalculateClaimableYield() public {
        uint256 day = 1;
        uint256 userBalance = 3000e6;
        uint256 totalSupply = 10000e6;
        uint256 totalYield = 100e6;
        uint256 expectedYield = (totalYield * userBalance) / totalSupply;

        // Post snapshot
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: bytes32(uint256(0x123)),
            totalSupply: totalSupply,
            cumulativeYield: totalYield
        });

        vm.prank(owner);
        chainBalanceManager.updateDailySnapshot(day, snapshots);

        // Calculate claimable
        uint256 claimable = chainBalanceManager.calculateClaimableYield(day, address(usdc), userBalance);
        assertEq(claimable, expectedYield);
    }

    function test_GetVaultRatio_Default() public {
        // Should return default 8000 (80%) if not set
        assertEq(chainBalanceManager.getVaultRatio(), 8000);
    }

    function test_GetSnapshotTimestamp() public {
        uint256 day = 1;
        ChainBalanceManager.TokenSnapshot[] memory snapshots = new ChainBalanceManager.TokenSnapshot[](1);
        snapshots[0] = ChainBalanceManager.TokenSnapshot({
            token: address(usdc),
            merkleRoot: bytes32(uint256(0x123)),
            totalSupply: 10000e6,
            cumulativeYield: 100e6
        });

        vm.prank(owner);
        chainBalanceManager.updateDailySnapshot(day, snapshots);

        uint256 timestamp = chainBalanceManager.getSnapshotTimestamp(day);
        assertEq(timestamp, block.timestamp);
    }
}
