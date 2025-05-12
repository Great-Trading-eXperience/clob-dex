// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";

import {MockToken} from "../../src/mocks/MockToken.sol";
import {MockWETH} from "../../src/mocks/MockWETH.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {VotingEscrowMainchain} from "../../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VotingControllerUpg} from "../../src/incentives/voting-controller/VotingControllerUpg.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GaugeControllerMainchainUpg} from
    "../../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import {GTXMarketMakerFactory} from "../../src/marketmaker/GTXMarketMakerFactory.sol";
import {GTXMarketMakerVault} from "../../src/marketmaker/GTXMarketMakerVault.sol";
import {BalanceManager} from "../../src/BalanceManager.sol";
import {PoolManager} from "../../src/PoolManager.sol";
import {GTXRouter} from "../../src/GTXRouter.sol";
import {OrderBook} from "../../src/OrderBook.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract GaugeTest is Test {
    uint256 private constant WEEK = 1 weeks;

    // Main tokens
    MockToken public token;         // Reward token
    MockWETH public weth;           // Base currency (WETH)
    MockUSDC public usdc;           // Quote currency (USDC)
    
    // Core protocol contracts
    VotingEscrowMainchain public votingEscrow;
    VotingControllerUpg public votingController;
    GaugeControllerMainchainUpg public gaugeController;
    
    // GTX infrastructure contracts
    BalanceManager public balanceManager;
    PoolManager public poolManager;
    GTXRouter public router;
    UpgradeableBeacon public orderBookBeacon;
    
    // Market maker contracts
    GTXMarketMakerFactory public marketMakerFactory;
    GTXMarketMakerVault public marketMakerVault;
    address public vaultImplementation;

    function setUp() public {
        // Set up mock tokens
        token = new MockToken("Test Token", "TEST", 18);
        token.mint(address(this), 1000e18);
        
        weth = new MockWETH();
        weth.mint(address(this), 100e18);
        
        usdc = new MockUSDC();
        usdc.mint(address(this), 200000e6); // 200k USDC
        
        // Set up voting escrow
        votingEscrow = new VotingEscrowMainchain(address(token), address(0), 1e6);

        // Set up voting controller
        address votingControllerImp =
            address(new VotingControllerUpg(address(votingEscrow), address(0)));
        votingController = VotingControllerUpg(
            address(
                new TransparentUpgradeableProxy(
                    votingControllerImp,
                    address(this),
                    abi.encodeWithSelector(VotingControllerUpg.initialize.selector, 100_000)
                )
            )
        );

        // Set up GTX infrastructure
        
        // 1. Balance Manager
        balanceManager = new BalanceManager();
        balanceManager.initialize(address(this), address(this), 20, 30); // 0.2% maker fee, 0.3% taker fee
        
        // 2. OrderBook Beacon
        OrderBook orderBookImpl = new OrderBook();
        orderBookBeacon = new UpgradeableBeacon(address(orderBookImpl), address(this));
        
        // 3. Pool Manager
        poolManager = new PoolManager();
        poolManager.initialize(address(this), address(balanceManager), address(orderBookBeacon));
        
        // 4. Router
        router = new GTXRouter();
        router.initialize(address(this), address(poolManager));
        
        // Set router in pool manager
        poolManager.setRouter(address(router));
        
        // Set up vault implementation
        vaultImplementation = address(new GTXMarketMakerVault());
        
        // Set up market maker factory
        marketMakerFactory = new GTXMarketMakerFactory();
        marketMakerFactory.initialize(
            address(this),
            address(votingEscrow),
            address(gaugeController),
            address(router),
            address(poolManager),
            address(balanceManager),
            vaultImplementation
        );

        // Set up gauge controller
        address gaugeControllerImp = address(
            new GaugeControllerMainchainUpg(
                address(votingController), address(token), address(marketMakerFactory)
            )
        );
        gaugeController = GaugeControllerMainchainUpg(
            address(
                new TransparentUpgradeableProxy(
                    gaugeControllerImp,
                    address(this),
                    abi.encodeWithSelector(GaugeControllerMainchainUpg.initialize.selector)
                )
            )
        );

        // Fund gauge controller
        token.mint(address(gaugeController), 1000e18);
        token.approve(address(gaugeController), 1000e18);
        gaugeController.fundToken(1000e18);

        // Set token per second
        votingController.setTokenPerSec(1);

        // Update factory with gauge controller address
        marketMakerFactory.updateGaugeAddresses(address(votingEscrow), address(gaugeController));
        
        // Create market maker vault with recommended parameters
        address mmVault = marketMakerFactory.createVaultWithRecommendedParams(
            "WETH-USDC Market Maker", 
            "MM-WETH-USDC",
            address(weth),
            address(usdc)
        );
        marketMakerVault = GTXMarketMakerVault(mmVault);

        // Approve tokens for deposit
        weth.approve(address(marketMakerVault), 50e18);
        usdc.approve(address(marketMakerVault), 100000e6);
        
        // Deposit to market maker (base and quote)
        marketMakerVault.deposit(10e18, 20000e6);

        // Add to destination contracts
        votingController.addDestinationContract(address(gaugeController), block.chainid);

        // Add market maker vault to voting controller
        votingController.addPool(uint64(block.chainid), address(marketMakerVault));

        // Lock token for voting power
        token.mint(address(this), 100e18);
        token.approve(address(votingEscrow), 100e18);
        uint256 timeInWeeks = (block.timestamp / WEEK) * WEEK;
        votingEscrow.increaseLockPosition(100e18, uint128(timeInWeeks + 50 * WEEK));

        // Vote for the market maker vault
        address[] memory pools = new address[](1);
        pools[0] = address(marketMakerVault);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 1e18;
        votingController.vote(pools, weights);

        // Advance time and finalize epoch
        vm.warp(block.timestamp + 1 days + WEEK);
        votingController.finalizeEpoch();
        votingController.broadcastResults(uint64(block.chainid));
    }

    function test_redeemRewards() public {
        // Advance time to accumulate rewards
        vm.warp(block.timestamp + WEEK / 2);
        
        // Check rewards
        uint256 balanceBefore = token.balanceOf(address(this));
        marketMakerVault.redeemRewards();
        uint256 balanceAfter = token.balanceOf(address(this));
        
        // Verify rewards were received
        assertGt(balanceAfter, balanceBefore);
    }

    function test_factoryParameterConstraints() public {
        // Test updating parameter constraints
        marketMakerFactory.updateParameterConstraints(
            1000,   // minTargetRatio (10%)
            9000,   // maxTargetRatio (90%)
            5,      // minSpread (0.05%)
            500,    // maxSpread (5%)
            0.01e18,// minOrderSize
            100e18, // maxOrderSize
            10,     // minSlippageTolerance (0.1%)
            200,    // maxSlippageTolerance (2%)
            2,      // minActiveOrders
            100,    // maxActiveOrders
            5 minutes, // minRebalanceInterval
            7 days     // maxRebalanceInterval
        );
        
        // Verify constraints were updated
        (
            uint256 minTargetRatio,
            uint256 maxTargetRatio,
            uint256 minSpread,
            uint256 maxSpread,
            uint256 minOrderSize,
            uint256 maxOrderSize,
            uint256 minSlippageTolerance,
            uint256 maxSlippageTolerance,
            uint256 minActiveOrders,
            uint256 maxActiveOrders,
            uint256 minRebalanceInterval,
            uint256 maxRebalanceInterval
        ) = marketMakerFactory.getParameterConstraints();
        
        // Assert constraints match what we set
        assertEq(minTargetRatio, 1000);
        assertEq(maxTargetRatio, 9000);
        assertEq(minSpread, 5);
        assertEq(maxSpread, 500);
        assertEq(minOrderSize, 0.01e18);
        assertEq(maxOrderSize, 100e18);
        assertEq(minSlippageTolerance, 10);
        assertEq(maxSlippageTolerance, 200);
        assertEq(minActiveOrders, 2);
        assertEq(maxActiveOrders, 100);
        assertEq(minRebalanceInterval, 5 minutes);
        assertEq(maxRebalanceInterval, 7 days);
    }
    
    function test_createVaultWithCustomParameters() public {
        // Create vault with custom parameters
        uint256[7] memory params = [
            uint256(3000),    // targetRatio (30%)
            uint256(30),      // spread (0.3%)
            uint256(10),      // minSpread (0.1%)
            uint256(5e18),    // maxOrderSize
            uint256(50),      // slippageTolerance (0.5%)
            uint256(4),       // minActiveOrders
            uint256(2 hours)  // rebalanceInterval
        ];
        
        address customVault = marketMakerFactory.createVault(
            "Custom WETH-USDC Market Maker",
            "CUSTOM-MM-WETH-USDC",
            address(weth),
            address(usdc),
            params
        );
        
        // Verify vault was created
        assertTrue(marketMakerFactory.isValidVault(customVault));
        
        // Deposit to new vault
        GTXMarketMakerVault vault = GTXMarketMakerVault(customVault);
        weth.approve(address(vault), 5e18);
        usdc.approve(address(vault), 10000e6);
        vault.deposit(5e18, 10000e6);
        
        // Verify deposit worked
        assertGt(vault.balanceOf(address(this)), 0);
    }
    
    function test_upgradeVaultImplementation() public {
        // Deploy new implementation
        address newImpl = address(new GTXMarketMakerVault());
        
        // Upgrade
        marketMakerFactory.updateVaultImplementation(newImpl);
        
        // Verify implementation was updated
        assertEq(marketMakerFactory.getVaultImplementation(), newImpl);
    }
}