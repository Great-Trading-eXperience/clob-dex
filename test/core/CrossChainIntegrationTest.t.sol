// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {MockToken} from "../../src/mocks/MockToken.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {ChainBalanceManager} from "../../src/core/ChainBalanceManager.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {HyperlaneMessages} from "../../src/core/libraries/HyperlaneMessages.sol";

contract MockMailbox {
    event Dispatch(uint32 destinationDomain, bytes32 recipient, bytes message);
    
    function dispatch(uint32 destinationDomain, bytes32 recipient, bytes calldata messageBody) external payable returns (bytes32) {
        emit Dispatch(destinationDomain, recipient, messageBody);
        return keccak256(messageBody);
    }
}

contract CrossChainIntegrationTest is Test {
    BalanceManager balanceManager;
    ChainBalanceManager chainBalanceManager;
    MockToken sourceToken;
    MockToken syntheticToken;
    MockMailbox mailbox;
    
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    
    uint32 constant RARI_DOMAIN = 1_918_988_905;
    uint32 constant APPCHAIN_DOMAIN = 4661;
    
    event CrossChainDepositReceived(address indexed user, Currency indexed currency, uint256 amount, uint32 sourceChain);
    event CrossChainWithdrawSent(address indexed user, Currency indexed currency, uint256 amount, uint32 targetChain);
    event BridgeToSynthetic(address indexed user, address indexed sourceToken, address indexed syntheticToken, uint256 amount);
    event WithdrawMessageReceived(address indexed user, address indexed token, uint256 amount);

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy tokens and mailbox
        sourceToken = new MockToken("USDC", "USDC", 6);
        syntheticToken = new MockToken("gsUSDC", "gsUSDC", 6);
        mailbox = new MockMailbox();
        
        // Deploy BalanceManager (destination chain - Rari)
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, 25, 50))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));
        
        // Deploy ChainBalanceManager (source chain - Appchain)
        (BeaconProxy chainBMProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainBalanceManager()),
            owner,
            abi.encodeWithSignature(
                "initialize(address,address,uint32,address)",
                owner,
                address(mailbox),
                RARI_DOMAIN,
                address(balanceManager)
            )
        );
        chainBalanceManager = ChainBalanceManager(address(chainBMProxy));
        
        // Initialize cross-chain on BalanceManager
        balanceManager.initializeCrossChain(address(mailbox), RARI_DOMAIN);
        balanceManager.setChainBalanceManager(APPCHAIN_DOMAIN, address(chainBalanceManager));
        
        // Configure ChainBalanceManager
        chainBalanceManager.addToken(address(sourceToken));
        chainBalanceManager.setTokenMapping(address(sourceToken), address(syntheticToken));
        
        // Setup test balances
        sourceToken.mint(user, 1000e6); // 1000 USDC
        syntheticToken.mint(address(balanceManager), 1000e6); // Mint synthetics to BalanceManager for testing
        
        vm.stopPrank();
    }

    function test_CrossChainDeposit() public {
        uint256 depositAmount = 100e6; // 100 USDC
        
        vm.startPrank(user);
        
        // Approve and deposit to vault (this automatically bridges to synthetic)
        sourceToken.approve(address(chainBalanceManager), depositAmount);
        
        // Expect the BridgeToSynthetic event to be emitted during deposit
        vm.expectEmit(true, true, true, true);
        emit BridgeToSynthetic(user, address(sourceToken), address(syntheticToken), depositAmount);
        
        chainBalanceManager.deposit(address(sourceToken), depositAmount, user);
        
        // Verify nonce incremented
        assertEq(chainBalanceManager.getUserNonce(user), 1);
        
        vm.stopPrank();
    }

    function test_CrossChainMessageHandling() public {
        uint256 amount = 50e6; // 50 USDC
        uint256 nonce = 123;
        
        // Create deposit message (simulating message from ChainBalanceManager)
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: address(syntheticToken),
            user: user,
            amount: amount,
            sourceChainId: APPCHAIN_DOMAIN,
            nonce: nonce
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 sender = bytes32(uint256(uint160(address(chainBalanceManager))));
        
        // Simulate Hyperlane mailbox call
        vm.startPrank(address(mailbox));
        
        vm.expectEmit(true, true, true, true);
        emit CrossChainDepositReceived(user, Currency.wrap(address(syntheticToken)), amount, APPCHAIN_DOMAIN);
        
        balanceManager.handle(APPCHAIN_DOMAIN, sender, messageBody);
        
        // Verify synthetic token balance credited
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(syntheticToken))), amount);
        
        vm.stopPrank();
    }

    function test_CrossChainWithdraw() public {
        uint256 withdrawAmount = 25e6; // 25 USDC
        
        // Setup: Give user synthetic tokens
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(this), true);
        vm.stopPrank();
        
        vm.startPrank(address(this));
        syntheticToken.mint(address(this), 100e6);
        syntheticToken.approve(address(balanceManager), 100e6);
        balanceManager.deposit(Currency.wrap(address(syntheticToken)), 100e6, address(this), user);
        vm.stopPrank();
        
        // Verify initial balance
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(syntheticToken))), 100e6);
        
        vm.startPrank(user);
        
        vm.expectEmit(true, true, true, true);
        emit CrossChainWithdrawSent(user, Currency.wrap(address(syntheticToken)), withdrawAmount, APPCHAIN_DOMAIN);
        
        balanceManager.requestWithdraw(
            Currency.wrap(address(syntheticToken)),
            withdrawAmount,
            APPCHAIN_DOMAIN,
            user
        );
        
        // Verify synthetic tokens burned
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(syntheticToken))), 75e6);
        
        // Verify nonce incremented
        assertEq(balanceManager.getUserNonce(user), 1);
        
        vm.stopPrank();
    }

    function test_WithdrawMessageHandling() public {
        uint256 amount = 30e6; // 30 USDC
        uint256 nonce = 456;
        
        // Setup: Deposit tokens to vault first
        vm.startPrank(user);
        sourceToken.approve(address(chainBalanceManager), 100e6);
        chainBalanceManager.deposit(address(sourceToken), 100e6, user);
        vm.stopPrank();
        
        // Create withdraw message (simulating message from BalanceManager)
        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.WithdrawMessage({
            messageType: HyperlaneMessages.WITHDRAW_MESSAGE,
            syntheticToken: address(syntheticToken),
            recipient: user,
            amount: amount,
            targetChainId: APPCHAIN_DOMAIN,
            nonce: nonce
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 sender = bytes32(uint256(uint160(address(balanceManager))));
        
        // Simulate Hyperlane mailbox call
        vm.startPrank(address(mailbox));
        
        vm.expectEmit(true, true, true, true);
        emit WithdrawMessageReceived(user, address(sourceToken), amount);
        
        chainBalanceManager.handle(RARI_DOMAIN, sender, messageBody);
        
        // Verify tokens unlocked for withdrawal
        assertEq(chainBalanceManager.getUnlockedBalance(user, address(sourceToken)), amount);
        
        vm.stopPrank();
        
        // User can now claim unlocked tokens
        vm.startPrank(user);
        uint256 userBalanceBefore = sourceToken.balanceOf(user);
        
        chainBalanceManager.claim(address(sourceToken), amount);
        
        assertEq(sourceToken.balanceOf(user), userBalanceBefore + amount);
        assertEq(chainBalanceManager.getUnlockedBalance(user, address(sourceToken)), 0);
        
        vm.stopPrank();
    }

    function test_ReplayProtection() public {
        uint256 amount = 10e6;
        uint256 nonce = 789;
        
        // Create message
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: address(syntheticToken),
            user: user,
            amount: amount,
            sourceChainId: APPCHAIN_DOMAIN,
            nonce: nonce
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 sender = bytes32(uint256(uint160(address(chainBalanceManager))));
        
        vm.startPrank(address(mailbox));
        
        // First message should succeed
        balanceManager.handle(APPCHAIN_DOMAIN, sender, messageBody);
        assertEq(balanceManager.getBalance(user, Currency.wrap(address(syntheticToken))), amount);
        
        // Second identical message should fail (replay protection)
        vm.expectRevert("Message already processed");
        balanceManager.handle(APPCHAIN_DOMAIN, sender, messageBody);
        
        vm.stopPrank();
    }

    function test_UnauthorizedSender() public {
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: address(syntheticToken),
            user: user,
            amount: 10e6,
            sourceChainId: APPCHAIN_DOMAIN,
            nonce: 1
        });
        
        bytes memory messageBody = abi.encode(message);
        bytes32 wrongSender = bytes32(uint256(uint160(makeAddr("attacker"))));
        
        vm.startPrank(address(mailbox));
        
        vm.expectRevert("Invalid sender");
        balanceManager.handle(APPCHAIN_DOMAIN, wrongSender, messageBody);
        
        vm.stopPrank();
    }

    function test_CrossChainConfiguration() public {
        // Test mailbox configuration
        (address mailboxAddr, uint32 localDomain) = balanceManager.getMailboxConfig();
        assertEq(mailboxAddr, address(mailbox));
        assertEq(localDomain, RARI_DOMAIN);
        
        // Test chain balance manager configuration
        assertEq(balanceManager.getChainBalanceManager(APPCHAIN_DOMAIN), address(chainBalanceManager));
        
        // Test token mapping
        assertEq(chainBalanceManager.getTokenMapping(address(sourceToken)), address(syntheticToken));
        assertEq(chainBalanceManager.getReverseTokenMapping(address(syntheticToken)), address(sourceToken));
    }
}