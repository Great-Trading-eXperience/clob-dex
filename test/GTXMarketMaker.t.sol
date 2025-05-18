// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {OrderBook} from "../src/OrderBook.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {BalanceManager} from "../src/BalanceManager.sol";
import {GTXRouter} from "../src/GTXRouter.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {GTXMarketMakerFactory} from "../src/marketmaker/GTXMarketMakerFactory.sol";
import {GTXMarketMakerVault} from "../src/marketmaker/GTXMarketMakerVault.sol";
import {GTXMarketMakerVaultStorage} from "../src/marketmaker/GTXMarketMakerVaultStorage.sol";
import {GTXMarketMakerFactoryStorage} from "../src/marketmaker/GTXMarketMakerFactoryStorage.sol";
import {Currency} from "../src/libraries/Currency.sol";
import {PoolIdLibrary, PoolKey} from "../src/libraries/Pool.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IGTXRouter} from "../src/interfaces/IGTXRouter.sol";
import {IBalanceManager} from "../src/interfaces/IBalanceManager.sol";
import {GaugeControllerMainchainUpg} from "../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {GTXToken} from "../src/token/GTXToken.sol";
import {VotingEscrowMainchain} from "../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {VotingControllerUpg} from "../src/incentives/voting-controller/VotingControllerUpg.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

contract GTXMarketMakerTest is Test {
    // Constants
    uint256 private constant WEEK = 1 weeks;

    // Test wallets
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address treasury = makeAddr("treasury");

    // Tokens
    MockToken weth;
    MockToken usdc;
    GTXToken gtxToken;
    VotingEscrowMainchain veToken;
    VotingControllerUpg public votingController;

    // Mocked infrastructure
    GaugeControllerMainchainUpg gaugeController;
    OrderBook orderBook;
    PoolManager poolManager;
    GTXRouter router;
    BalanceManager balanceManager;

    // Contracts to test
    GTXMarketMakerFactory factory;
    GTXMarketMakerVault vaultImpl;
    GTXMarketMakerVault vault;

    // Fees
    uint256 private feeMaker = 1; // 0.1%
    uint256 private feeTaker = 5; // 0.5%
    uint256 constant FEE_UNIT = 1000;

    // Constants for testing
    uint256 private initialBalance = 1000 ether;
    uint256 private initialBalanceUSDC = 10e6;
    uint256 private initialBalanceWETH = 1e18;
    uint256 constant BASE_AMOUNT = 10 * 10 ** 18; 
    uint256 constant QUOTE_AMOUNT = 20_000 * 10 ** 6; // 20,000 USDC

    // Default parameters
    uint256 targetRatio = 5000; // 50%
    uint256 spread = 50; // 0.5%
    uint256 minSpread = 10; // 0.1%
    uint256 maxOrderSize = 1 * 10 ** 18; // 1 ETH
    uint256 slippageTolerance = 50; // 0.5%
    uint256 minActiveOrders = 4; // At least 4 orders
    uint256 rebalanceInterval = 1 hours; // 1 hour

    // Default trading rules
    IOrderBook.TradingRules private defaultTradingRules;

    event ParametersUpdated(uint256 targetRatio, uint256 spread, uint256 minSpread, uint256 maxOrderSize, uint256 slippageTolerance, uint256 minActiveOrders);

    function setUp() public {
        weth = new MockToken("Wrapped Ether", "WETH", 18);
        usdc = new MockToken("USD Coin", "USDC", 6);
        gtxToken = new GTXToken();

        // Deploy voting escrow
        veToken = new VotingEscrowMainchain(address(gtxToken), address(0), 0);

        // Deploy voting controller via proxy
        VotingControllerUpg votingImpl = new VotingControllerUpg(
            address(veToken),
            address(0)
        );
        TransparentUpgradeableProxy votingProxy = new TransparentUpgradeableProxy(
                address(votingImpl),
                address(this),
                abi.encodeWithSelector(
                    VotingControllerUpg.initialize.selector,
                    100_000
                )
            );
        votingController = VotingControllerUpg(address(votingProxy));

        // Deploy real infrastructure
        BeaconDeployer beaconDeployer = new BeaconDeployer();

        // BalanceManager proxy
        (BeaconProxy balanceManagerProxy, ) = beaconDeployer
            .deployUpgradeableContract(
                address(new BalanceManager()),
                owner,
                abi.encodeCall(
                    BalanceManager.initialize,
                    (owner, owner, feeMaker, feeTaker)
                )
            );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        // OrderBook beacon
        IBeacon orderBookBeacon = new UpgradeableBeacon(
            address(new OrderBook()),
            owner
        );
        address orderBookBeaconAddress = address(orderBookBeacon);

        // PoolManager proxy
        (BeaconProxy poolManagerProxy, ) = beaconDeployer
            .deployUpgradeableContract(
                address(new PoolManager()),
                owner,
                abi.encodeCall(
                    PoolManager.initialize,
                    (
                        owner,
                        address(balanceManager),
                        address(orderBookBeaconAddress)
                    )
                )
            );
        poolManager = PoolManager(address(poolManagerProxy));

        // Router proxy
        (BeaconProxy routerProxy, ) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(
                GTXRouter.initialize,
                (address(poolManager), address(balanceManager))
            )
        );
        router = GTXRouter(address(routerProxy));

        Currency usdcCurrency = Currency.wrap(address(usdc));
        Currency wethCurrency = Currency.wrap(address(weth));

        vm.deal(owner, initialBalance);

        // Initialize default trading rules
        defaultTradingRules = IOrderBook.TradingRules({
            minTradeAmount: 1e14,
            minAmountMovement: 1e14,
            minOrderSize: 1e4,
            minPriceMovement: 1e4
        });

        // Use the actual owner address
        vm.startPrank(owner);
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        poolManager.setRouter(address(router));
        poolManager.addCommonIntermediary(usdcCurrency);
        poolManager.createPool(wethCurrency, usdcCurrency, defaultTradingRules);
        vm.stopPrank();

        vaultImpl = new GTXMarketMakerVault();

        vaultImpl = new GTXMarketMakerVault();
        address tempGaugeController = address(1);

        // Create the factory implementation
        GTXMarketMakerFactory factoryImpl = new GTXMarketMakerFactory();

        // Create a proxy for the factory using BeaconDeployer with the temporary gauge controller
        (BeaconProxy factoryProxy, address factoryBeacon) = beaconDeployer
            .deployUpgradeableContract(
                address(factoryImpl),
                owner,
                abi.encodeCall(
                    GTXMarketMakerFactory.initialize,
                    (
                        owner,
                        address(veToken),
                        tempGaugeController, 
                        address(router),
                        address(poolManager),
                        address(balanceManager),
                        address(vaultImpl)
                    )
                )
            );
        factory = GTXMarketMakerFactory(address(factoryProxy));

        // Now create the GaugeController with the factory address
        address gaugeControllerImpl = address(
            new GaugeControllerMainchainUpg(
                address(votingController),
                address(gtxToken),
                address(factory)
            )
        );

        // Create proxy for GaugeController
        TransparentUpgradeableProxy gaugeControllerProxy = new TransparentUpgradeableProxy(
                gaugeControllerImpl,
                address(this),
                abi.encodeWithSelector(
                    GaugeControllerMainchainUpg.initialize.selector
                )
            );
        gaugeController = GaugeControllerMainchainUpg(
            address(gaugeControllerProxy)
        );

        // Update the factory with the actual gauge controller address
        vm.startPrank(owner);
        factory.updateGaugeAddresses(
            address(veToken),
            address(gaugeController)
        );
        vm.stopPrank();

        // Fund gauge controller with tokens
        gtxToken.mint(address(gaugeController), 1000 * 10 ** 18);
        gtxToken.approve(address(gaugeController), 1000 * 10 ** 18);
        gaugeController.fundToken(1000 * 10 ** 18);

        // Set token per second
        votingController.setTokenPerSec(1);

        // Add to destination contracts
        votingController.addDestinationContract(
            address(gaugeController),
            block.chainid
        );

        // Create a vault
        vm.startPrank(owner);
        uint256[7] memory params = [
            targetRatio,
            spread,
            minSpread,
            maxOrderSize,
            slippageTolerance,
            minActiveOrders,
            rebalanceInterval
        ];

        address vaultAddress = factory.createVault(
            "ETH-USDC Market Maker Vault",
            "ETH-USDC-MMV",
            address(weth),
            address(usdc),
            params
        );

        vault = GTXMarketMakerVault(vaultAddress);
        vm.stopPrank();

        // Add market maker vault to voting controller
        votingController.addPool(uint64(block.chainid), address(vault));

        // Mint and lock token for voting power
        gtxToken.mint(address(this), 100 * 10 ** 18);
        gtxToken.approve(address(veToken), 100 * 10 ** 18);
        uint256 timeInWeeks = (block.timestamp / WEEK) * WEEK;
        veToken.increaseLockPosition(
            100 * 10 ** 18,
            uint128(timeInWeeks + 50 * WEEK)
        );

        // Vote for the market maker vault
        address[] memory pools = new address[](1);
        pools[0] = address(vault);
        uint64[] memory weights = new uint64[](1);
        weights[0] = 1e18;
        votingController.vote(pools, weights);

        // Advance time and finalize epoch
        vm.warp(block.timestamp + 1 days + WEEK);
        votingController.finalizeEpoch();
        votingController.broadcastResults(uint64(block.chainid));

        // Authorize the vault to interact with the balanceManager
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(vault), true);
        vm.stopPrank();
        
        // Mint tokens to users
        weth.mint(alice, 100 * 10 ** 18);
        usdc.mint(alice, 200_000 * 10 ** 6);
        weth.mint(bob, 100 * 10 ** 18);
        usdc.mint(bob, 200_000 * 10 ** 6);

        // Approve vault to spend user tokens
        vm.startPrank(alice);
        weth.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        weth.approve(address(vault), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        // Populate the orderbook with data from multiple traders
        _populateOrderBook();
    }

    // Helper function to populate the orderbook with data from multiple traders
    function _populateOrderBook() internal {
        // Create a pool for the market maker vault's trading pair
        IPoolManager.Pool memory pool = poolManager.getPool(
            PoolKey(Currency.wrap(address(weth)), Currency.wrap(address(usdc)))
        );

        // Create 20 traders for testing
        address[] memory traders = new address[](20);
        for (uint256 i = 0; i < 20; i++) {
            traders[i] = address(uint160(i + 2000));
            
            // Mint tokens to each trader
            vm.startPrank(traders[i]);
            weth.mint(traders[i], 100e18);
            usdc.mint(traders[i], 200_000e6); // Increased USDC for buy orders

            // Approve the balance manager to spend tokens
            IERC20(address(weth)).approve(address(balanceManager), 100e18);
            IERC20(address(usdc)).approve(address(balanceManager), 200_000e6);
            vm.stopPrank();
        }

        // Place buy orders at different price levels (lower than current price)
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(traders[i]);
            uint128 price = uint128(1950e6 - (i + 1) * 10e6); // Starting from 1940 USDC per ETH and going down

            // For buy orders, quantity is in base asset (ETH)
            uint128 buyQuantity = 2e18; // 2 ETH

            router.placeOrderWithDeposit(
                pool,
                price,
                buyQuantity,
                IOrderBook.Side.BUY,
                traders[i]
            );
            vm.stopPrank();
        }

        // Place sell orders at different price levels (higher than current price)
        for (uint256 i = 10; i < 20; i++) {
            vm.startPrank(traders[i]);
            uint128 price = uint128(2050e6 + (i - 10) * 10e6); // Starting from 2050 USDC per ETH and going up

            // For sell orders, quantity is in base asset (ETH)
            uint128 sellQuantity = 2e18; // 2 ETH

            router.placeOrderWithDeposit(
                pool,
                price,
                sellQuantity,
                IOrderBook.Side.SELL,
                traders[i]
            );
            vm.stopPrank();
        }

        // Verify the orderbook has been populated
        IOrderBook.PriceVolume memory bestBid = router.getBestPrice(
            Currency.wrap(address(weth)),
            Currency.wrap(address(usdc)),
            IOrderBook.Side.BUY
        );

        IOrderBook.PriceVolume memory bestAsk = router.getBestPrice(
            Currency.wrap(address(weth)),
            Currency.wrap(address(usdc)),
            IOrderBook.Side.SELL
        );
    }

    function test_FactoryInitialization() public {
        (
            address veTokenAddr,
            address gaugeControllerAddr,
            address routerAddr,
            address poolManagerAddr,
            address balanceManagerAddr
        ) = factory.getInfrastructureAddresses();

        assertEq(veTokenAddr, address(veToken));
        assertEq(gaugeControllerAddr, address(gaugeController));
        assertEq(routerAddr, address(router));
        assertEq(poolManagerAddr, address(poolManager));
        assertEq(balanceManagerAddr, address(balanceManager));

        (
            uint256 minTargetRatio,
            uint256 maxTargetRatio,
            uint256 minSpreadValue,
            uint256 maxSpreadValue,
            uint256 minOrderSizeValue,
            uint256 maxOrderSizeValue,
            uint256 minSlippageToleranceValue,
            uint256 maxSlippageToleranceValue,
            uint256 minActiveOrdersValue,
            uint256 maxActiveOrdersValue,
            uint256 minRebalanceIntervalValue,
            uint256 maxRebalanceIntervalValue
        ) = factory.getParameterConstraints();

        assertEq(minTargetRatio, 1000);
        assertEq(maxTargetRatio, 9000);
        assertEq(minSpreadValue, 5);
        assertEq(maxSpreadValue, 500);
        assertEq(minOrderSizeValue, 0.01 * 10 ** 18);
        assertEq(maxOrderSizeValue, 100 * 10 ** 18);
        assertEq(minSlippageToleranceValue, 10);
        assertEq(maxSlippageToleranceValue, 200);
        assertEq(minActiveOrdersValue, 2);
        assertEq(maxActiveOrdersValue, 100);
        assertEq(minRebalanceIntervalValue, 5 minutes);
        assertEq(maxRebalanceIntervalValue, 7 days);
    }

    function test_VaultCreation() public {
        assertTrue(factory.isValidVault(address(vault)));
        assertEq(vault.name(), "ETH-USDC Market Maker Vault");
        assertEq(vault.symbol(), "ETH-USDC-MMV");
        assertEq(vault.owner(), owner);
    }

    function test_CreateVaultWithRecommendedParams() public {
        vm.startPrank(owner);

        address vaultAddress = factory.createVaultWithRecommendedParams(
            "Recommended ETH-USDC Vault",
            "REC-ETH-USDC",
            address(weth),
            address(usdc)
        );

        vm.stopPrank();

        assertTrue(factory.isValidVault(vaultAddress));

        GTXMarketMakerVault recVault = GTXMarketMakerVault(vaultAddress);
        assertEq(recVault.name(), "Recommended ETH-USDC Vault");
        assertEq(recVault.symbol(), "REC-ETH-USDC");
        assertEq(recVault.owner(), owner);
    }

    function test_VaultDeposit() public {
        weth.mint(alice, BASE_AMOUNT);
        usdc.mint(alice, QUOTE_AMOUNT);

        vm.startPrank(alice);

        weth.approve(address(vault), BASE_AMOUNT);
        usdc.approve(address(vault), QUOTE_AMOUNT);

        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);

        assertEq(vault.getAvailableBaseBalance(), BASE_AMOUNT);
        assertEq(vault.getAvailableQuoteBalance(), QUOTE_AMOUNT);

        uint256 lpTokens = vault.balanceOf(alice);
        assertGt(lpTokens, 0);

        vm.stopPrank();
    }
    
    function test_MultipleDeposits() public {
        weth.mint(alice, BASE_AMOUNT);
        usdc.mint(alice, QUOTE_AMOUNT);
        weth.mint(bob, BASE_AMOUNT);
        usdc.mint(bob, QUOTE_AMOUNT);

        vm.startPrank(alice);
        weth.approve(address(vault), BASE_AMOUNT);
        usdc.approve(address(vault), QUOTE_AMOUNT);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 aliceLp = vault.balanceOf(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        weth.approve(address(vault), BASE_AMOUNT);
        usdc.approve(address(vault), QUOTE_AMOUNT);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 bobLp = vault.balanceOf(bob);
        vm.stopPrank();

        assertApproxEqRel(bobLp, aliceLp, 0.001e18);
    }

    function test_Withdraw() public {
        vm.startPrank(alice);

        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 lpTokens = vault.balanceOf(alice);

        uint256 beforeWethBalance = weth.balanceOf(alice);
        uint256 beforeUsdcBalance = usdc.balanceOf(alice);

        vault.withdraw(lpTokens / 2);

        uint256 afterWethBalance = weth.balanceOf(alice);
        uint256 afterUsdcBalance = usdc.balanceOf(alice);

        assertApproxEqRel(
            afterWethBalance - beforeWethBalance,
            BASE_AMOUNT / 2,
            0.01e18
        );
        assertApproxEqRel(
            afterUsdcBalance - beforeUsdcBalance,
            QUOTE_AMOUNT / 2,
            0.01e18
        );

        assertApproxEqAbs(vault.balanceOf(alice), lpTokens / 2, 1);

        vm.stopPrank();
    }

    function test_WithdrawWithLockedFunds() public {
        vm.startPrank(alice);

        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 lpTokens = vault.balanceOf(alice);

        vm.stopPrank();

        vm.startPrank(owner);
        
        uint128 sellPrice = 2100 * 10 ** 6;
        uint128 sellQuantity = uint128(BASE_AMOUNT / 2);
        uint48 sellOrderId = vault.placeOrder(
            sellPrice,
            sellQuantity,
            IOrderBook.Side.SELL
        );
        
        uint128 buyPrice = 1900 * 10 ** 6;
        uint128 buyQuantity = uint128(BASE_AMOUNT / 2);
        uint48 buyOrderId = vault.placeOrder(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );
        
        vm.stopPrank();
        
        uint256 lockedBase = vault.getLockedBaseBalance();
        uint256 lockedQuote = vault.getLockedQuoteBalance();
        uint256 availableBase = vault.getAvailableBaseBalance();
        uint256 availableQuote = vault.getAvailableQuoteBalance();
        
        assertGt(lockedBase, 0);
        assertGt(lockedQuote, 0);
        
        assertApproxEqRel(availableBase + lockedBase, BASE_AMOUNT, 0.05e18);
        assertApproxEqRel(availableQuote + lockedQuote, QUOTE_AMOUNT, 0.05e18); // Within 5%

        vm.startPrank(alice);

        uint256 beforeWethBalance = weth.balanceOf(alice);
        uint256 beforeUsdcBalance = usdc.balanceOf(alice);
        
        vault.withdraw(lpTokens / 2);
        
        uint256 afterWethBalance = weth.balanceOf(alice);
        uint256 afterUsdcBalance = usdc.balanceOf(alice);
        
        vm.stopPrank();
        
        uint256 lockedBaseAfter = vault.getLockedBaseBalance();
        uint256 lockedQuoteAfter = vault.getLockedQuoteBalance();
     
        vm.startPrank(alice);

        assertApproxEqRel(
            afterWethBalance - beforeWethBalance,
            BASE_AMOUNT / 2,
            0.01e18
        );
        assertApproxEqRel(
            afterUsdcBalance - beforeUsdcBalance,
            QUOTE_AMOUNT / 2,
            0.01e18
        );

        assertApproxEqAbs(vault.balanceOf(alice), lpTokens / 2, 1);

        vm.stopPrank();
    }

    function test_PlaceOrder() public {
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        uint128 buyPrice = 1900 * 10 ** 6; 
        uint128 buyQuantity = 1 * 10 ** 18; 
        uint48 buyOrderId = vault.placeOrder(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );

        assertGt(uint256(buyOrderId), 0);

        uint128 sellPrice = 2100 * 10 ** 6; 
        uint128 sellQuantity = 1 * 10 ** 18; 
        uint48 sellOrderId = vault.placeOrder(
            sellPrice,
            sellQuantity,
            IOrderBook.Side.SELL
        );

        assertGt(uint256(sellOrderId), 0);

        vm.stopPrank();
    }

    function test_PlaceMarketOrder() public {
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        uint128 buyQuantity = 1 * 10 ** 18;
        uint48 buyOrderId = vault.placeMarketOrder(
            buyQuantity,
            IOrderBook.Side.BUY
        );

        assertGt(uint256(buyOrderId), 0);

        uint128 sellQuantity = 1 * 10 ** 18;
        uint48 sellOrderId = vault.placeMarketOrder(
            sellQuantity,
            IOrderBook.Side.SELL
        );

        assertGt(uint256(sellOrderId), 0);

        vm.stopPrank();
    }

    function test_CancelOrder() public {
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        uint128 buyPrice = 1900 * 10 ** 6; 
        uint128 buyQuantity = 1 * 10 ** 18; 
        uint48 buyOrderId = vault.placeOrder(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );

        IOrderBook.Order memory orderBefore = vault.getOrder(buyOrderId);
        uint128 remainingQuantity = orderBefore.quantity - orderBefore.filled;
        uint256 expectedUnlockedAmount = (uint256(remainingQuantity) * orderBefore.price) / (10 ** 18);
        uint256 balanceBefore = vault.getAvailableQuoteBalance();

        vm.expectEmit(true, true, true, true);
        emit IOrderBook.OrderCancelled(buyOrderId, address(vault), uint48(block.timestamp), IOrderBook.Status.CANCELLED);

        vault.cancelOrder(buyOrderId);

        IOrderBook.Order memory orderAfter = vault.getOrder(buyOrderId);
        assertEq(uint256(orderAfter.status), uint256(IOrderBook.Status.CANCELLED), "Order status should be CANCELLED");

        uint256 balanceAfter = vault.getAvailableQuoteBalance();
        assertGe(balanceAfter - balanceBefore, expectedUnlockedAmount, "Funds should be unlocked in BalanceManager");

        vm.stopPrank();
    }

    function test_UpdateParams() public {
        vm.startPrank(owner);

        uint256 newTargetRatioVal = 6000;
        uint256 newSpreadVal = 100;
        uint256 newMinSpreadVal = 20;
        uint256 newMaxOrderSizeVal = 2 * 10 ** 18;
        uint256 newSlippageToleranceVal = 100;
        uint256 newMinActiveOrdersVal = 6; 

        vm.expectEmit(true, true, true, true);
        emit ParametersUpdated(
            newTargetRatioVal,
            newSpreadVal,
            newMinSpreadVal,
            newMaxOrderSizeVal,
            newSlippageToleranceVal,
            newMinActiveOrdersVal
        );

        vault.updateParams(
            newTargetRatioVal,
            newSpreadVal,
            newMinSpreadVal,
            newMaxOrderSizeVal,
            newSlippageToleranceVal,
            newMinActiveOrdersVal
        );

        assertEq(vault.targetRatio(), newTargetRatioVal);
        assertEq(vault.spread(), newSpreadVal);
        assertEq(vault.minSpread(), newMinSpreadVal);
        assertEq(vault.maxOrderSize(), newMaxOrderSizeVal);
        assertEq(vault.slippageTolerance(), newSlippageToleranceVal);
        assertEq(vault.minActiveOrders(), newMinActiveOrdersVal);

        vm.stopPrank();
    }

    function test_FactoryUpdateImplementation() public {
        vm.startPrank(owner);

        GTXMarketMakerVault newImpl = new GTXMarketMakerVault();

        address oldImpl = factory.getVaultImplementation();
        factory.updateVaultImplementation(address(newImpl));
        address updatedImpl = factory.getVaultImplementation();

        assertEq(updatedImpl, address(newImpl));
        assertNotEq(updatedImpl, oldImpl);

        vm.stopPrank();
    }

    function test_UpdateInfrastructure() public {
        vm.startPrank(owner);

        BeaconDeployer dele = new BeaconDeployer();
        UpgradeableBeacon newOrderBookBeacon = new UpgradeableBeacon(
            address(new OrderBook()),
            owner
        );

        (BeaconProxy newBalanceManagerProxy, ) = dele.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, 0, 0))
        );
        BalanceManager newBalanceManager = BalanceManager(
            address(newBalanceManagerProxy)
        );

        (BeaconProxy newPoolManagerProxy, ) = dele.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(
                PoolManager.initialize,
                (owner, address(newBalanceManager), address(newOrderBookBeacon))
            )
        );
        PoolManager newPoolManager = PoolManager(address(newPoolManagerProxy));

        (BeaconProxy newRouterProxy, ) = dele.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(
                GTXRouter.initialize,
                (address(newPoolManager), address(newBalanceManager))
            )
        );
        GTXRouter newRouter = GTXRouter(address(newRouterProxy));

        factory.updateInfrastructure(
            address(newRouter),
            address(newPoolManager),
            address(newBalanceManager)
        );

        (
            ,
            ,
            address routerAddr,
            address poolManagerAddr,
            address balanceManagerAddr
        ) = factory.getInfrastructureAddresses();

        assertEq(routerAddr, address(newRouter));
        assertEq(poolManagerAddr, address(newPoolManager));
        assertEq(balanceManagerAddr, address(newBalanceManager));

        vm.stopPrank();
    }

    function test_UpdateParameterConstraints() public {
        vm.startPrank(owner);

        factory.updateParameterConstraints(
            2000,
            8000,
            10,
            400,
            0.1 * 10 ** 18,
            50 * 10 ** 18,
            20,
            150,
            3,
            80,
            10 minutes,
            3 days
        );

        (
            uint256 minTargetRatio,
            uint256 maxTargetRatio,
            uint256 minSpread,
            uint256 maxSpread,
            uint256 minOrderSize,
            uint256 maxOrderSize,
            uint256 minSlippageTolerance,
            uint256 maxSlippageTolerance,
            uint256 minActiveOrdersParam,
            uint256 maxActiveOrders,
            uint256 minRebalanceInterval,
            uint256 maxRebalanceInterval
        ) = factory.getParameterConstraints();

        assertEq(minTargetRatio, 2000);
        assertEq(maxTargetRatio, 8000);
        assertEq(minSpread, 10);
        assertEq(maxSpread, 400);
        assertEq(minOrderSize, 0.1 * 10 ** 18);
        assertEq(maxOrderSize, 50 * 10 ** 18);
        assertEq(minSlippageTolerance, 20);
        assertEq(maxSlippageTolerance, 150);
        assertEq(minActiveOrdersParam, 3);
        assertEq(maxActiveOrders, 80);
        assertEq(minRebalanceInterval, 10 minutes);
        assertEq(maxRebalanceInterval, 3 days);

        vm.stopPrank();
    }

    function test_GetTotalValue() public {
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        uint256 totalValue = vault.getTotalValue();

        uint256 expectedValue = (BASE_AMOUNT * 2000 * 10 ** 6) /
            10 ** 18 +
            QUOTE_AMOUNT;

        assertApproxEqRel(totalValue, expectedValue, 0.05e18);
    }

    function test_Rebalance() public {
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();
        vm.expectRevert();
        vm.prank(alice);
        vault.rebalance();

        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(alice);
        vault.rebalance();
    }

    function test_SetRebalanceInterval() public {
        vm.startPrank(owner);

        uint256 newInterval = 30 minutes;
        vault.setRebalanceInterval(newInterval);

        vm.stopPrank();
    }

    function test_GetBestPrice() public {
        IOrderBook.PriceVolume memory bestBid = vault.getBestPrice(
            IOrderBook.Side.BUY
        );

        assertEq(bestBid.price, 1940 * 10 ** 6);
        assertEq(bestBid.volume, 2 * 10 ** 18);

        IOrderBook.PriceVolume memory bestAsk = vault.getBestPrice(
            IOrderBook.Side.SELL
        );

        assertEq(bestAsk.price, 2050 * 10 ** 6); 
        assertEq(bestAsk.volume, 2 * 10 ** 18); 
    }

    function test_CurrentPrice() public {
        uint128 currentPrice = vault.getCurrentPrice();

        uint128 expectedPrice = uint128((1940 * 10 ** 6 + 2050 * 10 ** 6) / 2);

        assertEq(currentPrice, expectedPrice);
    }

    function test_ValidateSpread() public {
        bool isValid = vault.validateSpread(
            1940 * 10 ** 6,
            IOrderBook.Side.BUY
        );
        assertTrue(isValid);

        isValid = vault.validateSpread(2049 * 10 ** 6, IOrderBook.Side.BUY);
        assertFalse(isValid);

        isValid = vault.validateSpread(2060 * 10 ** 6, IOrderBook.Side.SELL);
        assertTrue(isValid);

        isValid = vault.validateSpread(1941 * 10 ** 6, IOrderBook.Side.SELL);
        assertFalse(isValid);
    }

    function test_AccessControl() public {
        vm.startPrank(alice);
        vm.expectRevert();
        vault.updateParams(
            6000,
            100,
            20,
            2 * 10 ** 18,
            100,
            6
        );
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert();
        vault.placeOrder(
            1900 * 10 ** 6,
            1 * 10 ** 18,
            IOrderBook.Side.BUY
        );
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert();
        vault.setRebalanceInterval(30 minutes);
        vm.stopPrank();
    }

    function test_UpgradeableVault() public {
        vm.startPrank(owner);

        GTXMarketMakerVault newImpl = new GTXMarketMakerVault();

        factory.updateVaultImplementation(address(newImpl));

        uint256[7] memory params = [
            targetRatio,
            spread,
            minSpread,
            maxOrderSize,
            slippageTolerance,
            minActiveOrders,
            rebalanceInterval
        ];

        address newVaultAddress = factory.createVault(
            "Upgraded ETH-USDC Vault",
            "UP-ETH-USDC",
            address(weth),
            address(usdc),
            params
        );

        vault.updateParams(
            6000,
            100,
            20,
            2 * 10 ** 18,
            100,
            6
        );

        GTXMarketMakerVault newVault = GTXMarketMakerVault(newVaultAddress);
        newVault.updateParams(
            4000,
            80,
            15,
            3 * 10 ** 18,
            75,
            8
        );

        vm.stopPrank();
    }
}
