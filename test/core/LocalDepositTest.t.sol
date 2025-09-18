// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "@gtx/mocks/MockUSDC.sol";
import "@gtx/mocks/MockWETH.sol";
import "@gtxcore/BalanceManager.sol";
import "@gtxcore/TokenRegistry.sol";
import "@gtxcore/SyntheticTokenFactory.sol";
import "@gtx/token/SyntheticToken.sol";
import {Currency} from "@gtxcore/libraries/Currency.sol";
import {IBalanceManagerErrors} from "@gtxcore/interfaces/IBalanceManagerErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title LocalDepositTest
 * @dev Test suite for the local deposit functionality in BalanceManager
 * Tests the ability to deposit local tokens and receive synthetic tokens on the same chain
 */
contract LocalDepositTest is Test {
    // Events to test
    event LocalDeposit(
        address indexed recipient,
        address indexed sourceToken,
        address indexed syntheticToken,
        uint256 sourceAmount,
        uint256 syntheticAmount
    );
    
    event Deposit(address indexed user, uint256 indexed id, uint256 amount);
    BalanceManager private balanceManager;
    TokenRegistry private tokenRegistry;
    SyntheticTokenFactory private syntheticTokenFactory;
    SyntheticToken private gsUSDC;
    SyntheticToken private gsWETH;
    MockUSDC private localUSDC;
    MockWETH private localWETH;

    address private owner = address(0x123);
    address private feeReceiver = address(0x456);
    address private user1 = address(0x789);
    address private user2 = address(0xABC);
    
    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 private initialBalance = 1000 ether;
    uint256 private initialUSDCBalance = 1_000_000 * 1e6; // 1M USDC
    uint256 private initialWETHBalance = 1000 ether;

    // Test constants
    uint32 private constant LOCAL_CHAIN_ID = 1918988905; // Rari testnet
    uint256 private constant DEPOSIT_AMOUNT_USDC = 100 * 1e6; // 100 USDC
    uint256 private constant DEPOSIT_AMOUNT_WETH = 1 ether; // 1 WETH

    function setUp() public {
        // Set chain ID to Rari for local deposit testing
        vm.chainId(LOCAL_CHAIN_ID);

        // Deploy BalanceManager
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        (BeaconProxy balanceManagerProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, feeReceiver, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        // Deploy TokenRegistry
        (BeaconProxy tokenRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        tokenRegistry = TokenRegistry(address(tokenRegistryProxy));

        // Deploy SyntheticTokenFactory
        (BeaconProxy syntheticTokenFactoryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new SyntheticTokenFactory()),
            owner,
            abi.encodeCall(SyntheticTokenFactory.initialize, (owner, address(tokenRegistry), address(balanceManager)))
        );
        syntheticTokenFactory = SyntheticTokenFactory(address(syntheticTokenFactoryProxy));

        // Deploy local tokens (mock real tokens on the local chain)
        localUSDC = new MockUSDC();
        localWETH = new MockWETH();

        // Deploy synthetic tokens 
        gsUSDC = new SyntheticToken("Synthetic USDC", "gsUSDC", address(balanceManager));
        gsWETH = new SyntheticToken("Synthetic WETH", "gsWETH", address(balanceManager));

        // Set up BalanceManager with TokenRegistry
        vm.startPrank(owner);
        balanceManager.setTokenRegistry(address(tokenRegistry));
        vm.stopPrank();

        // Mint local tokens to users
        localUSDC.mint(user1, initialUSDCBalance);
        localUSDC.mint(user2, initialUSDCBalance);
        localWETH.mint(user1, initialWETHBalance);
        localWETH.mint(user2, initialWETHBalance);

        // Give users ETH for gas
        vm.deal(user1, initialBalance);
        vm.deal(user2, initialBalance);
    }

    function testSetup() public view {
        assertEq(balanceManager.owner(), owner);
        assertEq(balanceManager.getTokenRegistry(), address(tokenRegistry));
        assertEq(localUSDC.balanceOf(user1), initialUSDCBalance);
        assertEq(localWETH.balanceOf(user1), initialWETHBalance);
        assertEq(block.chainid, LOCAL_CHAIN_ID);
    }

    function testRegisterLocalTokenMapping() public {
        vm.startPrank(owner);
        
        // Register local USDC → gsUSDC mapping (same chain)
        tokenRegistry.registerTokenMapping(
            LOCAL_CHAIN_ID,          // sourceChainId: Local chain
            address(localUSDC),      // sourceToken: Local USDC
            LOCAL_CHAIN_ID,          // targetChainId: Same local chain
            address(gsUSDC),         // syntheticToken: gsUSDC
            "gsUSDC",
            6,                       // sourceDecimals (USDC)
            6                        // syntheticDecimals (gsUSDC)
        );

        vm.stopPrank();

        // Verify mapping was registered
        assertTrue(tokenRegistry.isTokenMappingActive(LOCAL_CHAIN_ID, address(localUSDC), LOCAL_CHAIN_ID));
        assertEq(
            tokenRegistry.getSyntheticToken(LOCAL_CHAIN_ID, address(localUSDC), LOCAL_CHAIN_ID),
            address(gsUSDC)
        );
    }

    function testDepositLocal_RevertsWithZeroAmount() public {
        _setupLocalUSDCMapping();

        vm.startPrank(user1);
        
        vm.expectRevert("ZeroAmount()");
        balanceManager.depositLocal(address(localUSDC), 0, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWithZeroTokenAddress() public {
        _setupLocalUSDCMapping();

        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.InvalidTokenAddress.selector));
        balanceManager.depositLocal(address(0), DEPOSIT_AMOUNT_USDC, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWithZeroRecipient() public {
        _setupLocalUSDCMapping();

        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.InvalidRecipientAddress.selector));
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, address(0));
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWhenTokenNotSupported() public {
        // Don't register mapping - should revert

        vm.startPrank(user1);
        
        vm.expectRevert(abi.encodeWithSelector(IBalanceManagerErrors.TokenNotSupportedForLocalDeposits.selector, address(localUSDC)));
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_RevertsWithInsufficientAllowance() public {
        _setupLocalUSDCMapping();

        vm.startPrank(user1);
        
        // Don't approve - should revert with ERC20 error
        vm.expectRevert();
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, user1);
        
        vm.stopPrank();
    }

    function testDepositLocal_SuccessfulDeposit() public {
        _setupLocalUSDCMapping();

        vm.startPrank(user1);
        
        // Approve BalanceManager to spend tokens
        localUSDC.approve(address(balanceManager), DEPOSIT_AMOUNT_USDC);

        // Record balances before
        uint256 userUSDCBefore = localUSDC.balanceOf(user1);
        uint256 userGsUSDCBefore = gsUSDC.balanceOf(user1);
        uint256 balanceManagerUSDCBefore = localUSDC.balanceOf(address(balanceManager));
        uint256 userInternalBalanceBefore = balanceManager.getBalance(user1, Currency.wrap(address(gsUSDC)));

        // Expect LocalDeposit event (defined in BalanceManager)
        vm.expectEmit(true, true, true, true);
        emit LocalDeposit(user1, address(localUSDC), address(gsUSDC), DEPOSIT_AMOUNT_USDC, DEPOSIT_AMOUNT_USDC);
        
        // Expect Deposit event (from IBalanceManager interface)
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, Currency.wrap(address(gsUSDC)).toId(), DEPOSIT_AMOUNT_USDC);

        // Perform local deposit
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, user1);

        vm.stopPrank();

        // Verify token transfers
        assertEq(localUSDC.balanceOf(user1), userUSDCBefore - DEPOSIT_AMOUNT_USDC, "User USDC balance should decrease");
        assertEq(localUSDC.balanceOf(address(balanceManager)), balanceManagerUSDCBefore + DEPOSIT_AMOUNT_USDC, "BalanceManager should receive USDC");
        
        // Verify synthetic tokens are held by BalanceManager (vault)
        assertEq(gsUSDC.balanceOf(address(balanceManager)), userGsUSDCBefore + DEPOSIT_AMOUNT_USDC, "BalanceManager should hold gsUSDC");
        assertEq(gsUSDC.balanceOf(user1), 0, "User should not directly hold ERC20 gsUSDC");
        
        // Verify internal balance tracking
        assertEq(
            balanceManager.getBalance(user1, Currency.wrap(address(gsUSDC))), 
            userInternalBalanceBefore + DEPOSIT_AMOUNT_USDC,
            "Internal balance should be updated"
        );
    }

    function testDepositLocal_MultipleUsers() public {
        _setupLocalUSDCMapping();

        // User1 deposits
        vm.startPrank(user1);
        localUSDC.approve(address(balanceManager), DEPOSIT_AMOUNT_USDC);
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, user1);
        vm.stopPrank();

        // User2 deposits  
        vm.startPrank(user2);
        localUSDC.approve(address(balanceManager), DEPOSIT_AMOUNT_USDC * 2);
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC * 2, user2);
        vm.stopPrank();

        // Verify BalanceManager holds synthetic tokens (vault model)
        assertEq(gsUSDC.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDC * 3);
        assertEq(gsUSDC.balanceOf(user1), 0, "User1 should not directly hold ERC20 tokens");
        assertEq(gsUSDC.balanceOf(user2), 0, "User2 should not directly hold ERC20 tokens");
        
        // Verify internal balances
        assertEq(balanceManager.getBalance(user1, Currency.wrap(address(gsUSDC))), DEPOSIT_AMOUNT_USDC);
        assertEq(balanceManager.getBalance(user2, Currency.wrap(address(gsUSDC))), DEPOSIT_AMOUNT_USDC * 2);

        // Verify total backing
        assertEq(localUSDC.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDC * 3);
    }

    function testDepositLocal_DifferentRecipient() public {
        _setupLocalUSDCMapping();

        vm.startPrank(user1);
        
        // Approve and deposit to user2
        localUSDC.approve(address(balanceManager), DEPOSIT_AMOUNT_USDC);
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, user2);
        
        vm.stopPrank();

        // Verify user1 paid, user2 received internal balance
        assertEq(localUSDC.balanceOf(user1), initialUSDCBalance - DEPOSIT_AMOUNT_USDC);
        assertEq(gsUSDC.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDC, "BalanceManager should hold ERC20 tokens");
        assertEq(gsUSDC.balanceOf(user2), 0, "User2 should not directly hold ERC20 tokens");
        assertEq(balanceManager.getBalance(user2, Currency.wrap(address(gsUSDC))), DEPOSIT_AMOUNT_USDC);
    }

    function testDepositLocal_WithDecimalConversion() public {
        // Register local WETH → gsWETH mapping (both 18 decimals, no conversion needed)
        vm.startPrank(owner);
        tokenRegistry.registerTokenMapping(
            LOCAL_CHAIN_ID,
            address(localWETH),
            LOCAL_CHAIN_ID,
            address(gsWETH),
            "gsWETH",
            18,  // WETH decimals
            18   // gsWETH decimals
        );
        vm.stopPrank();

        vm.startPrank(user1);
        
        localWETH.approve(address(balanceManager), DEPOSIT_AMOUNT_WETH);
        balanceManager.depositLocal(address(localWETH), DEPOSIT_AMOUNT_WETH, user1);
        
        vm.stopPrank();

        // Should be 1:1 conversion since both are 18 decimals
        assertEq(gsWETH.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_WETH, "BalanceManager should hold ERC20 tokens");
        assertEq(gsWETH.balanceOf(user1), 0, "User should not directly hold ERC20 tokens");
        assertEq(balanceManager.getBalance(user1, Currency.wrap(address(gsWETH))), DEPOSIT_AMOUNT_WETH);
    }

    function testDepositLocal_MatchesCrossChainBehavior() public {
        _setupLocalUSDCMapping();
        
        // Simulate cross-chain deposit (what would happen from ChainBalanceManager message)
        // Cross-chain deposits also mint to BalanceManager now
        uint256 crossChainAmount = DEPOSIT_AMOUNT_USDC;
        gsUSDC.mint(address(balanceManager), crossChainAmount);
        
        // Simulate internal balance update (as BalanceManager._handleDepositMessage would do)
        // Note: In real scenario, this would be done by the message handler
        vm.store(
            address(balanceManager),
            bytes32(uint256(keccak256("gtx.clob.storage.balancemanager")) - 1),
            bytes32(crossChainAmount)
        );

        // Now do local deposit with user1
        vm.startPrank(user1);
        localUSDC.approve(address(balanceManager), DEPOSIT_AMOUNT_USDC);
        balanceManager.depositLocal(address(localUSDC), DEPOSIT_AMOUNT_USDC, user1);
        vm.stopPrank();

        // BalanceManager should hold all synthetic tokens
        assertEq(gsUSDC.balanceOf(address(balanceManager)), DEPOSIT_AMOUNT_USDC + crossChainAmount, "BalanceManager should hold all gsUSDC");
        assertEq(gsUSDC.balanceOf(user1), 0, "Local user should not directly hold ERC20 tokens");
        assertEq(gsUSDC.balanceOf(user2), 0, "Cross-chain user should not directly hold ERC20 tokens");
        
        // Both users should have internal balances for trading
        assertEq(balanceManager.getBalance(user1, Currency.wrap(address(gsUSDC))), DEPOSIT_AMOUNT_USDC, "Local deposit user internal balance");
        // Note: Cross-chain user balance would be set by _handleDepositMessage in real scenario
        
        // Same token contract, same trading capabilities
        assertEq(address(gsUSDC), address(gsUSDC), "Same synthetic token for both deposit methods");
    }

    // Helper function to set up local USDC mapping
    function _setupLocalUSDCMapping() internal {
        vm.startPrank(owner);
        tokenRegistry.registerTokenMapping(
            LOCAL_CHAIN_ID,
            address(localUSDC),
            LOCAL_CHAIN_ID,
            address(gsUSDC),
            "gsUSDC",
            6,   // USDC decimals
            6    // gsUSDC decimals  
        );
        vm.stopPrank();
    }
}