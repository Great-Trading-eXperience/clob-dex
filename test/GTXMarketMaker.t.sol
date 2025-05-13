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
    uint256 constant BASE_AMOUNT = 10 * 10 ** 18; // 10 ETH
    uint256 constant QUOTE_AMOUNT = 20_000 * 10 ** 6; // 20,000 USDC

    // Default parameters - ensure they are within the valid ranges defined in the factory
    uint256 targetRatio = 5000; // 50% (valid range: 1000-9000)
    uint256 spread = 50; // 0.5% (valid range: 5-500)
    uint256 minSpread = 10; // 0.1% (must be >= 5)
    uint256 maxOrderSize = 1 * 10 ** 18; // 1 ETH (valid range: 0.01-100 ETH)
    uint256 slippageTolerance = 50; // 0.5% (valid range: 10-200)
    uint256 minActiveOrders = 4; // At least 4 orders (valid range: 2-100)
    uint256 rebalanceInterval = 1 hours; // 1 hour (valid range: 5 min - 7 days)

    // Default trading rules
    IOrderBook.TradingRules private defaultTradingRules;

    function setUp() public {
        // Deploy tokens
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

        // 1. BalanceManager proxy
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

        // 2. OrderBook beacon
        IBeacon orderBookBeacon = new UpgradeableBeacon(
            address(new OrderBook()),
            owner
        );
        address orderBookBeaconAddress = address(orderBookBeacon);

        // 3. PoolManager proxy
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

        // 4. Router proxy
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
            minTradeAmount: 1e14, // 0.0001 ETH
            minAmountMovement: 1e14, // 0.0001 ETH
            minOrderSize: 1e4, // 0.01 USDC
            minPriceMovement: 1e4 // 0.01 USDC with 6 decimals
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
                        tempGaugeController, // Use temporary non-zero address
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

        // Setup mock voting power for incentives
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
            traders[i] = address(uint160(i + 2000)); // Using different addresses than the main test accounts

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

        console2.log("Best bid price:", bestBid.price);
        console2.log("Best bid volume:", bestBid.volume);
        console2.log("Best ask price:", bestAsk.price);
        console2.log("Best ask volume:", bestAsk.volume);
    }

    function test_FactoryInitialization() public {
        // Get infrastructure addresses
        (
            address veTokenAddr,
            address gaugeControllerAddr,
            address routerAddr,
            address poolManagerAddr,
            address balanceManagerAddr
        ) = factory.getInfrastructureAddresses();

        // Verify addresses
        assertEq(veTokenAddr, address(veToken));
        assertEq(gaugeControllerAddr, address(gaugeController));
        assertEq(routerAddr, address(router));
        assertEq(poolManagerAddr, address(poolManager));
        assertEq(balanceManagerAddr, address(balanceManager));

        // Verify parameter constraints
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

        // Verify default constraints
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
        // Check that the vault is properly registered
        assertTrue(factory.isValidVault(address(vault)));

        // Verify basic vault properties
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

        // Check that the vault is properly registered
        assertTrue(factory.isValidVault(vaultAddress));

        // Verify basic vault properties
        GTXMarketMakerVault recVault = GTXMarketMakerVault(vaultAddress);
        assertEq(recVault.name(), "Recommended ETH-USDC Vault");
        assertEq(recVault.symbol(), "REC-ETH-USDC");
        assertEq(recVault.owner(), owner);
    }

    function test_VaultDeposit() public {
        // Mint tokens to Alice
        weth.mint(alice, BASE_AMOUNT);
        usdc.mint(alice, QUOTE_AMOUNT);

        vm.startPrank(alice);

        // Approve vault to spend tokens
        weth.approve(address(vault), BASE_AMOUNT);
        usdc.approve(address(vault), QUOTE_AMOUNT);

        // Initial deposit
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);

        // Check balances
        assertEq(vault.getAvailableBaseBalance(), BASE_AMOUNT);
        assertEq(vault.getAvailableQuoteBalance(), QUOTE_AMOUNT);

        // Check LP tokens
        uint256 lpTokens = vault.balanceOf(alice);
        assertGt(lpTokens, 0);

        vm.stopPrank();
    }
    
    function test_MultipleDeposits() public {
        // Mint tokens to Alice and Bob
        weth.mint(alice, BASE_AMOUNT);
        usdc.mint(alice, QUOTE_AMOUNT);
        weth.mint(bob, BASE_AMOUNT);
        usdc.mint(bob, QUOTE_AMOUNT);

        // Alice’s deposit
        vm.startPrank(alice);
        weth.approve(address(vault), BASE_AMOUNT);
        usdc.approve(address(vault), QUOTE_AMOUNT);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 aliceLp = vault.balanceOf(alice);
        vm.stopPrank();

        // Bob’s deposit
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

        // Initial deposit
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 lpTokens = vault.balanceOf(alice);

        // Before withdrawal
        uint256 beforeWethBalance = weth.balanceOf(alice);
        uint256 beforeUsdcBalance = usdc.balanceOf(alice);

        // Withdraw half
        vault.withdraw(lpTokens / 2);

        // After withdrawal
        uint256 afterWethBalance = weth.balanceOf(alice);
        uint256 afterUsdcBalance = usdc.balanceOf(alice);

        // Should get back approximately half of the deposited assets
        assertApproxEqRel(
            afterWethBalance - beforeWethBalance,
            BASE_AMOUNT / 2,
            0.01e18
        ); // Within 1%
        assertApproxEqRel(
            afterUsdcBalance - beforeUsdcBalance,
            QUOTE_AMOUNT / 2,
            0.01e18
        ); // Within 1%

        // Remaining LP tokens
        assertApproxEqAbs(vault.balanceOf(alice), lpTokens / 2, 1);

        vm.stopPrank();
    }

    function test_WithdrawWithLockedFunds() public {
        vm.startPrank(alice);

        // Initial deposit
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        uint256 lpTokens = vault.balanceOf(alice);

        vm.stopPrank();

        // Place orders to lock funds
        vm.startPrank(owner);
        
        // Place a sell order to lock base currency (ETH)
        uint128 sellPrice = 2100 * 10 ** 6;
        uint128 sellQuantity = uint128(BASE_AMOUNT / 2);
        uint48 sellOrderId = vault.placeOrder(
            sellPrice,
            sellQuantity,
            IOrderBook.Side.SELL
        );
        
        // Place a buy order to lock quote currency (USDC)
        uint128 buyPrice = 1900 * 10 ** 6;
        uint128 buyQuantity = uint128(BASE_AMOUNT / 2);
        uint48 buyOrderId = vault.placeOrder(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );
        
        vm.stopPrank();
        
        // Get the actual locked balances after order placement
        uint256 lockedBase = vault.getLockedBaseBalance();
        uint256 lockedQuote = vault.getLockedQuoteBalance();
        uint256 availableBase = vault.getAvailableBaseBalance();
        uint256 availableQuote = vault.getAvailableQuoteBalance();
        
        // Verify we have some locked funds
        assertGt(lockedBase, 0);
        assertGt(lockedQuote, 0);
        
        // Verify available balances + locked balances = total balances
        assertApproxEqRel(availableBase + lockedBase, BASE_AMOUNT, 0.05e18); // Within 5%
        assertApproxEqRel(availableQuote + lockedQuote, QUOTE_AMOUNT, 0.05e18); // Within 5%

        vm.startPrank(alice);

        // Before withdrawal
        uint256 beforeWethBalance = weth.balanceOf(alice);
        uint256 beforeUsdcBalance = usdc.balanceOf(alice);
        
        // The withdraw function should automatically cancel orders to free the locked funds
        vault.withdraw(lpTokens / 2);
        
        // After withdrawal
        uint256 afterWethBalance = weth.balanceOf(alice);
        uint256 afterUsdcBalance = usdc.balanceOf(alice);
        
        // Verify that the orders were cancelled by checking the locked balances
        vm.stopPrank();
        
        // Check that locked balances are reduced
        uint256 lockedBaseAfter = vault.getLockedBaseBalance();
        uint256 lockedQuoteAfter = vault.getLockedQuoteBalance();
        
        // Print values for debugging
        console2.log("Initial locked base:", lockedBase);
        console2.log("After locked base:", lockedBaseAfter);
        console2.log("Initial locked quote:", lockedQuote);
        console2.log("After locked quote:", lockedQuoteAfter);
        
        vm.startPrank(alice);

        // Should get back approximately half of the deposited assets
        assertApproxEqRel(
            afterWethBalance - beforeWethBalance,
            BASE_AMOUNT / 2,
            0.01e18
        ); // Within 1%
        assertApproxEqRel(
            afterUsdcBalance - beforeUsdcBalance,
            QUOTE_AMOUNT / 2,
            0.01e18
        ); // Within 1%

        // Remaining LP tokens should be approximately half
        assertApproxEqAbs(vault.balanceOf(alice), lpTokens / 2, 1); // Allow 1 wei difference due to rounding

        vm.stopPrank();
    }

    function test_PlaceOrder() public {
        // First make a deposit
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        // Place a buy order
        uint128 buyPrice = 1900 * 10 ** 6; // 1900 USDC per ETH
        uint128 buyQuantity = 1 * 10 ** 18; // 1 ETH
        uint48 buyOrderId = vault.placeOrder(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );

        // Verify order ID is non-zero
        assertGt(uint256(buyOrderId), 0);

        // Place a sell order
        uint128 sellPrice = 2100 * 10 ** 6; // 2100 USDC per ETH
        uint128 sellQuantity = 1 * 10 ** 18; // 1 ETH
        uint48 sellOrderId = vault.placeOrder(
            sellPrice,
            sellQuantity,
            IOrderBook.Side.SELL
        );

        // Verify order ID is non-zero
        assertGt(uint256(sellOrderId), 0);

        vm.stopPrank();
    }

    function test_PlaceOrderWithDeposit() public {
        // First make a deposit
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        // Place a buy order with deposit
        uint128 buyPrice = 1900 * 10 ** 6; // 1900 USDC per ETH
        uint128 buyQuantity = 1 * 10 ** 18; // 1 ETH
        uint48 buyOrderId = vault.placeOrderWithDeposit(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );

        // Verify order ID is non-zero
        assertGt(uint256(buyOrderId), 0);

        vm.stopPrank();
    }

    function test_PlaceMarketOrder() public {
        // First make a deposit
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        // Place a market buy order
        uint128 buyQuantity = 1 * 10 ** 18; // 1 ETH
        uint48 buyOrderId = vault.placeMarketOrder(
            buyQuantity,
            IOrderBook.Side.BUY
        );

        // Verify order ID is non-zero
        assertGt(uint256(buyOrderId), 0);

        vm.stopPrank();
    }

    function test_CancelOrder() public {
        // First make a deposit
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(owner);

        // Place an order
        uint128 buyPrice = 1900 * 10 ** 6; // 1900 USDC per ETH
        uint128 buyQuantity = 1 * 10 ** 18; // 1 ETH
        uint48 buyOrderId = vault.placeOrder(
            buyPrice,
            buyQuantity,
            IOrderBook.Side.BUY
        );

        // Cancel the order
        vault.cancelOrder(buyOrderId);

        vm.stopPrank();
    }

    function test_UpdateParams() public {
        vm.startPrank(owner);

        // Update parameters
        uint256 newTargetRatio = 6000; // 60%
        uint256 newSpread = 100; // 1%
        uint256 newMinSpread = 20; // 0.2%
        uint256 newMaxOrderSize = 2 * 10 ** 18; // 2 ETH
        uint256 newSlippageTolerance = 100; // 1%
        uint256 newMinActiveOrders = 6; // At least 6 orders

        vault.updateParams(
            newTargetRatio,
            newSpread,
            newMinSpread,
            newMaxOrderSize,
            newSlippageTolerance,
            newMinActiveOrders
        );

        vm.stopPrank();
    }

    function test_FactoryUpdateImplementation() public {
        vm.startPrank(owner);

        // Deploy a new implementation
        GTXMarketMakerVault newImpl = new GTXMarketMakerVault();

        // Update the implementation
        address oldImpl = factory.getVaultImplementation();
        factory.updateVaultImplementation(address(newImpl));
        address updatedImpl = factory.getVaultImplementation();

        // Verify the implementation was updated
        assertEq(updatedImpl, address(newImpl));
        assertNotEq(updatedImpl, oldImpl);

        vm.stopPrank();
    }

    function test_UpdateInfrastructure() public {
        vm.startPrank(owner);

        // Deploy fresh infrastructure via beacons/proxies
        BeaconDeployer dele = new BeaconDeployer();
        UpgradeableBeacon newOrderBookBeacon = new UpgradeableBeacon(
            address(new OrderBook()),
            owner
        );

        // New BalanceManager proxy
        (BeaconProxy newBalanceManagerProxy, ) = dele.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, 0, 0))
        );
        BalanceManager newBalanceManager = BalanceManager(
            address(newBalanceManagerProxy)
        );

        // New PoolManager proxy
        (BeaconProxy newPoolManagerProxy, ) = dele.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(
                PoolManager.initialize,
                (owner, address(newBalanceManager), address(newOrderBookBeacon))
            )
        );
        PoolManager newPoolManager = PoolManager(address(newPoolManagerProxy));

        // New Router proxy
        (BeaconProxy newRouterProxy, ) = dele.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(
                GTXRouter.initialize,
                (address(newPoolManager), address(newBalanceManager))
            )
        );
        GTXRouter newRouter = GTXRouter(address(newRouterProxy));

        // Update factory infrastructure
        factory.updateInfrastructure(
            address(newRouter),
            address(newPoolManager),
            address(newBalanceManager)
        );

        // Verify updates
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

        // Update parameter constraints
        factory.updateParameterConstraints(
            2000, // minTargetRatio
            8000, // maxTargetRatio
            10, // minSpread
            400, // maxSpread
            0.1 * 10 ** 18, // minOrderSize
            50 * 10 ** 18, // maxOrderSize
            20, // minSlippageTolerance
            150, // maxSlippageTolerance
            3, // minActiveOrders
            80, // maxActiveOrders
            10 minutes, // minRebalanceInterval
            3 days // maxRebalanceInterval
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
        // First make a deposit
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        // Get the total value
        uint256 totalValue = vault.getTotalValue();

        // Expected value based on price (2000 USDC per ETH)
        uint256 expectedValue = (BASE_AMOUNT * 2000 * 10 ** 6) /
            10 ** 18 +
            QUOTE_AMOUNT;

        // Value should be approximately as expected (difference due to pricing)
        assertApproxEqRel(totalValue, expectedValue, 0.05e18); // Within 5%
    }

    function test_Rebalance() public {
        // First make a deposit
        vm.startPrank(alice);
        vault.deposit(BASE_AMOUNT, QUOTE_AMOUNT);
        vm.stopPrank();

        // Call rebalance as owner
        vm.startPrank(owner);
        vault.rebalance();
        vm.stopPrank();

        // Non-owner can't rebalance too soon
        vm.expectRevert("Too soon");
        vm.prank(alice);
        vault.rebalance();

        // Move forward in time
        vm.warp(block.timestamp + 1 hours + 1);

        // Now non-owner can rebalance
        vm.prank(alice);
        vault.rebalance();
    }

    function test_SetRebalanceInterval() public {
        vm.startPrank(owner);

        // Set new rebalance interval
        uint256 newInterval = 30 minutes;
        vault.setRebalanceInterval(newInterval);

        vm.stopPrank();
    }

    function test_GetBestPrice() public {
        // Get best price for buy side
        IOrderBook.PriceVolume memory bestBid = vault.getBestPrice(
            IOrderBook.Side.BUY
        );

        // Verify price is as expected
        assertEq(bestBid.price, 1950 * 10 ** 6); // 1950 USDC per ETH
        assertEq(bestBid.volume, 10 * 10 ** 18); // 10 ETH

        // Get best price for sell side
        IOrderBook.PriceVolume memory bestAsk = vault.getBestPrice(
            IOrderBook.Side.SELL
        );

        // Verify price is as expected
        assertEq(bestAsk.price, 2050 * 10 ** 6); // 2050 USDC per ETH
        assertEq(bestAsk.volume, 10 * 10 ** 18); // 10 ETH
    }

    function test_CurrentPrice() public {
        // Get current price
        uint128 currentPrice = vault.getCurrentPrice();

        // Should be the mid price between bid and ask
        uint128 expectedPrice = uint128((1950 * 10 ** 6 + 2050 * 10 ** 6) / 2); // 2000 USDC per ETH

        assertEq(currentPrice, expectedPrice);
    }

    function test_ValidateSpread() public {
        // Buy price at 1940, with best ask at 2050
        // Spread = (2050 - 1940) / 2050 = 0.0537 = 5.37%
        bool isValid = vault.validateSpread(
            1940 * 10 ** 6,
            IOrderBook.Side.BUY
        );
        assertTrue(isValid);

        // Buy price at 2049, with best ask at 2050
        // Spread = (2050 - 2049) / 2050 = 0.00049 = 0.049%
        isValid = vault.validateSpread(2049 * 10 ** 6, IOrderBook.Side.BUY);
        assertFalse(isValid); // Too narrow

        // Sell price at 2060, with best bid at 1950
        // Spread = (2060 - 1950) / 2060 = 0.0534 = 5.34%
        isValid = vault.validateSpread(2060 * 10 ** 6, IOrderBook.Side.SELL);
        assertTrue(isValid);

        // Sell price at 1951, with best bid at 1950
        // Spread = (1951 - 1950) / 1951 = 0.00051 = 0.051%
        isValid = vault.validateSpread(1951 * 10 ** 6, IOrderBook.Side.SELL);
        assertFalse(isValid); // Too narrow
    }

    function test_AccessControl() public {
        // Non-owner can't update params
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.updateParams(
            6000, // targetRatio
            100, // spread
            20, // minSpread
            2 * 10 ** 18, // maxOrderSize
            100, // slippageTolerance
            6 // minActiveOrders
        );
        vm.stopPrank();

        // Non-owner can't place orders
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.placeOrder(
            1900 * 10 ** 6, // price
            1 * 10 ** 18, // quantity
            IOrderBook.Side.BUY
        );
        vm.stopPrank();

        // Non-owner can't set rebalance interval
        vm.startPrank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setRebalanceInterval(30 minutes);
        vm.stopPrank();
    }

    function test_UpgradeableVault() public {
        vm.startPrank(owner);

        // Deploy a new implementation with additional functionality
        GTXMarketMakerVault newImpl = new GTXMarketMakerVault();

        // Update the implementation
        factory.updateVaultImplementation(address(newImpl));

        // Create a new vault with the new implementation
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

        // Existing vault should continue to work with old implementation
        vault.updateParams(
            6000, // targetRatio
            100, // spread
            20, // minSpread
            2 * 10 ** 18, // maxOrderSize
            100, // slippageTolerance
            6 // minActiveOrders
        );

        // New vault should use new implementation
        GTXMarketMakerVault newVault = GTXMarketMakerVault(newVaultAddress);
        newVault.updateParams(
            4000, // targetRatio
            80, // spread
            15, // minSpread
            3 * 10 ** 18, // maxOrderSize
            75, // slippageTolerance
            8 // minActiveOrders
        );

        vm.stopPrank();
    }
}
