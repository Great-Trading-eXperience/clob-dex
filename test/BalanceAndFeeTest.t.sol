// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {OrderId, Quantity, Side} from "../src/types/Types.sol";
import {Currency} from "../src/types/Currency.sol";
import {PoolKey} from "../src/types/Pool.sol";
import {Price} from "../src/libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {GTXRouter} from "../src/GTXRouter.sol";
import {BalanceManager} from "../src/BalanceManager.sol";

contract BalanceAndFeeTest is Test {
    IPoolManager.Pool public pool; 
    OrderBook public orderBook;
    PoolKey public key;
    
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address david = address(0x4);

    address owner = address(0x5);
    address feeCollector = address(0x6);

    address baseTokenAddress;
    address quoteTokenAddress;

    Currency baseCurrency;
    Currency quoteCurrency;

    // Define fee structure - modifiable for different test scenarios
    uint256 feeMaker = 10; // 0.1% as basis points (10/10000)
    uint256 feeTaker = 20; // 0.2% as basis points (20/10000)
    uint256 lotSize = 1e18;
    uint256 maxOrderAmount = 500e18;

    GTXRouter router; 
    PoolManager poolManager;
    BalanceManager balanceManager;
    MockToken baseToken;
    MockToken quoteToken;

    function setUp() public {
        // Set up tokens
        baseToken = new MockToken("WETH", "WETH", 18);
        quoteToken = new MockToken("USDC", "USDC", 6);
        baseTokenAddress = address(baseToken);
        quoteTokenAddress = address(quoteToken);

        // Mint tokens to users
        uint256 initialAmount = 1_000_000_000e18;
        baseToken.mint(alice, initialAmount);
        baseToken.mint(bob, initialAmount);
        baseToken.mint(charlie, initialAmount);
        baseToken.mint(david, initialAmount);
        quoteToken.mint(alice, initialAmount);
        quoteToken.mint(bob, initialAmount);
        quoteToken.mint(charlie, initialAmount);
        quoteToken.mint(david, initialAmount);

        baseCurrency = Currency.wrap(baseTokenAddress);
        quoteCurrency = Currency.wrap(quoteTokenAddress);

        PoolKey memory poolKey = PoolKey({
            baseCurrency: Currency.wrap(baseTokenAddress),
            quoteCurrency: Currency.wrap(quoteTokenAddress)
        });

        // Initialize contracts with fee configuration
        balanceManager = new BalanceManager(owner, feeCollector, feeMaker, feeTaker);
        poolManager = new PoolManager(owner, address(balanceManager));
        router = new GTXRouter(address(poolManager), address(balanceManager));

        // Set up permissions and connections
        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));
        vm.stopPrank();

        // Approve token usage for all users
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;

        for (uint i = 0; i < users.length; i++) {
            vm.startPrank(users[i]);
            baseToken.approve(address(balanceManager), type(uint256).max);
            quoteToken.approve(address(balanceManager), type(uint256).max);
            vm.stopPrank();
        }
        
        // Create the pool
        poolManager.createPool(baseCurrency, quoteCurrency, lotSize, maxOrderAmount);

        key = poolManager.createPoolKey(
            baseCurrency,
            quoteCurrency
        );
        pool = poolManager.getPool(key);
        orderBook = OrderBook(address(pool.orderBook));
    }    

    function testMultipleOrderMatching() public {
        console.log("\n=== MULTIPLE ORDER MATCHING TEST ===");
        
        // Get initial balances for all participants
        uint256 aliceInitialBaseBalance = baseToken.balanceOf(alice);
        uint256 aliceInitialQuoteBalance = quoteToken.balanceOf(alice);
        uint256 bobInitialBaseBalance = baseToken.balanceOf(bob);
        uint256 bobInitialQuoteBalance = quoteToken.balanceOf(bob);
        uint256 charlieInitialBaseBalance = baseToken.balanceOf(charlie);
        uint256 charlieInitialQuoteBalance = quoteToken.balanceOf(charlie);
        uint256 davidInitialBaseBalance = baseToken.balanceOf(david);
        uint256 davidInitialQuoteBalance = quoteToken.balanceOf(david);
        uint256 feeCollectorInitialBalance = quoteToken.balanceOf(feeCollector);
        
        // Define order parameters
        Price alicePrice = Price.wrap(2505e8); // Best price
        Price charliePrice = Price.wrap(2502e8); // Middle price
        Price davidPrice = Price.wrap(2500e8); // Lowest price
        
        Quantity aliceQuantity = Quantity.wrap(2505 * (10 ** Quantity.wrap(1).decimals())); // 3000 USDC
        Quantity charlieQuantity = Quantity.wrap(2502 * (10 ** Quantity.wrap(1).decimals())); // 4500 USDC
        Quantity davidQuantity = Quantity.wrap(2500 * (10 ** Quantity.wrap(1).decimals())); // 5000 USDC
        
        // Calculate expected locked amounts
        uint256 aliceExpectedLocked = (Quantity.unwrap(aliceQuantity) * Price.unwrap(alicePrice)) / (10 ** (aliceQuantity.decimals()) * 10 ** (alicePrice.decimals())) * (10 ** (MockToken(Currency.unwrap(quoteCurrency)).decimals()));
        uint256 charlieExpectedLocked = (Quantity.unwrap(charlieQuantity) * Price.unwrap(charliePrice)) / (10 ** (charlieQuantity.decimals()) * 10 ** (alicePrice.decimals())) * (10 ** (MockToken(Currency.unwrap(quoteCurrency)).decimals()));
        uint256 davidExpectedLocked = (Quantity.unwrap(davidQuantity) * Price.unwrap(davidPrice)) / (10 ** (davidQuantity.decimals()) * 10 ** (alicePrice.decimals())) * (10 ** (MockToken(Currency.unwrap(quoteCurrency)).decimals()));
        
        console.log("Alice quantity", Quantity.unwrap(aliceQuantity));
        console.log("Alice expected locked", aliceExpectedLocked);

        // Create a series of buy orders at different price levels from multiple users
        vm.startPrank(alice);
        console.log("--- Alice places buy order at 2505 USDC per WETH (3000 USDC) ---");
        router.placeOrderWithDeposit(
            baseCurrency, 
            quoteCurrency, 
            alicePrice,
            aliceQuantity,  
            Side.BUY, 
            alice
        );
        vm.stopPrank();
        
        // Verify Alice's quote token was locked
        uint256 aliceLockedAfterOrder = balanceManager.getLockedBalance(alice, address(orderBook), quoteCurrency);
        console.log("aliceExpectedLocked", aliceExpectedLocked);
        assertEq(aliceLockedAfterOrder, aliceExpectedLocked, "Alice's locked amount incorrect");
        
        // Verify Alice's wallet balance decreased
        assertApproxEqAbs(
            aliceInitialQuoteBalance - quoteToken.balanceOf(alice),
            aliceExpectedLocked,
            100,
            "Alice's wallet balance should have decreased by locked amount"
        );
        
        vm.startPrank(charlie);
        console.log("--- Charlie places buy order at 2502 USDC per WETH (4500 USDC) ---");
        router.placeOrderWithDeposit(
            baseCurrency, 
            quoteCurrency, 
            charliePrice,
            charlieQuantity,  
            Side.BUY, 
            charlie
        );
        vm.stopPrank();
        
        // Verify Charlie's quote token was locked
        uint256 charlieLockedAfterOrder = balanceManager.getLockedBalance(charlie, address(orderBook), quoteCurrency);
        assertEq(charlieLockedAfterOrder, charlieExpectedLocked, "Charlie's locked amount incorrect");
        
        vm.startPrank(david);
        console.log("--- David places buy order at 2500 USDC per WETH (5000 USDC) ---");
        router.placeOrderWithDeposit(
            baseCurrency, 
            quoteCurrency, 
            davidPrice,
            davidQuantity,  
            Side.BUY, 
            david
        );
        vm.stopPrank();
        
        // Verify David's quote token was locked
        uint256 davidLockedAfterOrder = balanceManager.getLockedBalance(david, address(orderBook), quoteCurrency);
        assertEq(davidLockedAfterOrder, davidExpectedLocked, "David's locked amount incorrect");
        
        // Log balances after buy orders from multiple users
        console.log("--- Balances After Multiple Users Place Buy Orders ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);
        
        // Calculate expected values - should match against all buy orders from best price first
        uint256 expectedMatchVolume = Quantity.unwrap(aliceQuantity) + Quantity.unwrap(charlieQuantity) + Quantity.unwrap(davidQuantity);
        uint256 aliceTradeValue = (Price.unwrap(alicePrice) * Quantity.unwrap(aliceQuantity)) / 1e8;
        uint256 charlieTradeValue = (Price.unwrap(charliePrice) * Quantity.unwrap(charlieQuantity)) / 1e8;
        uint256 davidTradeValue = (Price.unwrap(davidPrice) * Quantity.unwrap(davidQuantity)) / 1e8;
        uint256 expectedBaseValue = aliceTradeValue + charlieTradeValue + davidTradeValue;
        
        // Calculate expected fees
        uint256 aliceMakerFee = (aliceTradeValue * feeMaker) / 10000;
        uint256 charlieMakerFee = (charlieTradeValue * feeMaker) / 10000;
        uint256 davidMakerFee = (davidTradeValue * feeMaker) / 10000;
        uint256 totalMakerFee = aliceMakerFee + charlieMakerFee + davidMakerFee;
        
        uint256 bobTakerFee = (expectedBaseValue * feeTaker) / 10000;
        
        // Verify order book has correct orders
        (uint48 orderCountAlice, uint256 volumeAlice) = orderBook.getOrderQueue(Side.BUY, alicePrice);
        (uint48 orderCountCharlie, uint256 volumeCharlie) = orderBook.getOrderQueue(Side.BUY, charliePrice);
        (uint48 orderCountDavid, uint256 volumeDavid) = orderBook.getOrderQueue(Side.BUY, davidPrice);
        
        assertEq(orderCountAlice, 1, "Should be 1 order at Alice's price");
        assertEq(orderCountCharlie, 1, "Should be 1 order at Charlie's price");
        assertEq(orderCountDavid, 1, "Should be 1 order at David's price");
        
        assertEq(volumeAlice, Quantity.unwrap(aliceQuantity), "Volume at Alice's price incorrect");
        assertEq(volumeCharlie, Quantity.unwrap(charlieQuantity), "Volume at Charlie's price incorrect");
        assertEq(volumeDavid, Quantity.unwrap(davidQuantity), "Volume at David's price incorrect");
        
        // Bob places a market sell order that should match against all orders
        vm.startPrank(bob);
        console.log("\n--- Bob places market sell order for 10 WETH ---");
        router.placeMarketOrderWithDeposit(
            baseCurrency, 
            quoteCurrency, 
            Price.wrap(2495e8), // Minimum acceptable price
            Quantity.wrap(10e18), // 10 WETH (should match against all buy orders)
            Side.SELL, 
            bob
        );
        vm.stopPrank();
        
        // Log final balances for all users
        console.log("\n--- Final Balances After Multiple Matching ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);
        
        // VERIFY BALANCES AFTER MATCHING
        
        // 1. Verify fee collector received correct fees
        uint256 feeCollectorBalance = quoteToken.balanceOf(feeCollector);
        assertApproxEqAbs(
            feeCollectorBalance - feeCollectorInitialBalance, 
            totalMakerFee + bobTakerFee, 
            100, 
            "Fee collector balance incorrect"
        );
        
        // 2. Verify Bob's balances
        // Bob should have:
        // - Decreased base token (WETH) by 10 ETH
        // - Increased quote token (USDC) by expectedBaseValue - takerFee
        uint256 bobBaseDecrease = bobInitialBaseBalance - baseToken.balanceOf(bob);
        uint256 bobQuoteIncrease = quoteToken.balanceOf(bob) - bobInitialQuoteBalance;
        uint256 bobQuoteInContract = balanceManager.getBalance(bob, quoteCurrency);
        
        assertApproxEqAbs(
            bobBaseDecrease, 
            expectedMatchVolume, 
            100, 
            "Bob's base token decrease incorrect"
        );
        
        assertApproxEqAbs(
            bobQuoteIncrease + bobQuoteInContract, 
            expectedBaseValue - bobTakerFee, 
            100, 
            "Bob's quote token increase incorrect"
        );
        
        // 3. Verify Alice received her base tokens
        uint256 aliceBaseIncrease = baseToken.balanceOf(alice) - aliceInitialBaseBalance;
        uint256 aliceBaseInContract = balanceManager.getBalance(alice, baseCurrency);
        
        assertApproxEqAbs(
            aliceBaseIncrease + aliceBaseInContract, 
            Quantity.unwrap(aliceQuantity), 
            100, 
            "Alice didn't receive correct base tokens"
        );
        
        // 4. Verify Alice's locked quote tokens were spent
        uint256 aliceRemainingLocked = balanceManager.getLockedBalance(alice, address(orderBook), quoteCurrency);
        assertEq(aliceRemainingLocked, 0, "Alice should have no remaining locked balance");
        
        // 5. Verify Charlie received his base tokens
        uint256 charlieBaseIncrease = baseToken.balanceOf(charlie) - charlieInitialBaseBalance;
        uint256 charlieBaseInContract = balanceManager.getBalance(charlie, baseCurrency);
        
        assertApproxEqAbs(
            charlieBaseIncrease + charlieBaseInContract, 
            Quantity.unwrap(charlieQuantity), 
            100, 
            "Charlie didn't receive correct base tokens"
        );
        
        // 6. Verify David received his base tokens
        uint256 davidBaseIncrease = baseToken.balanceOf(david) - davidInitialBaseBalance;
        uint256 davidBaseInContract = balanceManager.getBalance(david, baseCurrency);
        
        assertApproxEqAbs(
            davidBaseIncrease + davidBaseInContract, 
            Quantity.unwrap(davidQuantity), 
            100, 
            "David didn't receive correct base tokens"
        );
        
        // Check that orderbook is now empty at those price levels
        (uint48 orderCount1, uint256 volume1) = orderBook.getOrderQueue(Side.BUY, alicePrice);
        (uint48 orderCount2, uint256 volume2) = orderBook.getOrderQueue(Side.BUY, charliePrice);
        (uint48 orderCount3, uint256 volume3) = orderBook.getOrderQueue(Side.BUY, davidPrice);
        
        assertEq(orderCount1, 0, "Orders should be fully matched at price 2505");
        assertEq(orderCount2, 0, "Orders should be fully matched at price 2502");
        assertEq(orderCount3, 0, "Orders should be fully matched at price 2500");
        
        assertEq(volume1, 0, "Volume should be zero at price 2505");
        assertEq(volume2, 0, "Volume should be zero at price 2502");
        assertEq(volume3, 0, "Volume should be zero at price 2500");
        
        console.log("\n--- Verification Results ---");
        console.log("Alice's trade:");
        console.log("  Amount: 3000 USDC at 2505 USDC/WETH = ", aliceTradeValue / 1e6, "USDC");
        console.log("  Maker fee: ", aliceMakerFee / 1e6, "USDC");
        
        console.log("Charlie's trade:");
        console.log("  Amount: 4500 USDC at 2502 USDC/WETH = ", charlieTradeValue / 1e6, "USDC");
        console.log("  Maker fee: ", charlieMakerFee / 1e6, "USDC");
        
        console.log("David's trade:");
        console.log("  Amount: 5000 USDC at 2500 USDC/WETH = ", davidTradeValue / 1e6, "USDC");
        console.log("  Maker fee: ", davidMakerFee / 1e6, "USDC");
        
        console.log("Bob's total:");
        console.log("  Sold: 10 WETH");
        console.log("  Received: ", (expectedBaseValue - bobTakerFee) / 1e6, "USDC");
        console.log("  Taker fee: ", bobTakerFee / 1e6, "USDC");
        
        console.log("Fee collector received:");
        console.log("  Total maker fees: ", totalMakerFee / 1e6, "USDC");
        console.log("  Total taker fees: ", bobTakerFee / 1e6, "USDC");
        console.log("  Total fees: ", (totalMakerFee + bobTakerFee) / 1e6, "USDC");
        
        console.log("Total trade value:", expectedBaseValue / 1e6, "USDC");
    }

    function testChangeFeesAndValidate() public {
        console.log("\n=== CHANGE FEES AND VALIDATE TEST ===");
        
        // Initial orders from multiple users
        vm.startPrank(alice);
        router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            Price.wrap(2500e8),
            Quantity.wrap(3e18),
            Side.BUY,
            alice
        );
        vm.stopPrank();
        
        vm.startPrank(charlie);
        router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            Price.wrap(2510e8),
            Quantity.wrap(4e18),
            Side.BUY,
            charlie
        );
        vm.stopPrank();
        
        vm.startPrank(david);
        router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            Price.wrap(2520e8),
            Quantity.wrap(3e18),
            Side.BUY,
            david
        );
        vm.stopPrank();
        
        // Log balances and current fees
        console.log("--- Initial Setup ---");
        console.log("Current maker fee:", feeMaker, "bps");
        console.log("Current taker fee:", feeTaker, "bps");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);
        
        // Bob places a market sell order with current fee structure
        vm.startPrank(bob);
        console.log("\n--- Bob places first market sell order with original fees ---");
        router.placeMarketOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            Price.wrap(2495e8),
            Quantity.wrap(3e18),
            Side.SELL,
            bob
        );
        vm.stopPrank();
        
        // Calculate expected fees for first trade
        uint256 firstTradeValue = 3e18 * 2520e8 / 1e8; // Should match with David's order at 2520
        uint256 firstExpectedMakerFee = (firstTradeValue * feeMaker) / 10000;
        uint256 firstExpectedTakerFee = (firstTradeValue * feeTaker) / 10000;
        
        // Log balances after first trade
        console.log("--- Balances after first trade with original fees ---");
        logBalance("Bob", bob);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);
        
        // Change fees (as owner)
        vm.startPrank(owner);
        uint256 newMakerFee = 5;  // 0.05%
        uint256 newTakerFee = 30; // 0.3%
        console.log("\n--- Changing Fees ---");
        console.log("New maker fee:", newMakerFee, "bps");
        console.log("New taker fee:", newTakerFee, "bps");
        
        balanceManager.setFees(newMakerFee, newTakerFee);
        vm.stopPrank();
        
        // Second market sell order from Bob after fee change
        vm.startPrank(bob);
        console.log("\n--- Bob places second market sell order after fee change ---");
        router.placeMarketOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            Price.wrap(2495e8),
            Quantity.wrap(4e18),
            Side.SELL,
            bob
        );
        vm.stopPrank();
        
        // Calculate expected fees for second trade
        uint256 secondTradeValue = 4e18 * 2510e8 / 1e8; // Should match with Charlie's order at 2510
        uint256 secondExpectedMakerFee = (secondTradeValue * newMakerFee) / 10000;
        uint256 secondExpectedTakerFee = (secondTradeValue * newTakerFee) / 10000;
        
        // Log final balances
        console.log("\n--- Final Balances After Second Order with New Fees ---");
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("Fee Collector", feeCollector);
        
        // Verify fee collector received correct fees
        uint256 feeCollectorBalance = quoteToken.balanceOf(feeCollector);
        uint256 totalExpectedFees = firstExpectedMakerFee + firstExpectedTakerFee + 
                                    secondExpectedMakerFee + secondExpectedTakerFee;
        
        assertApproxEqAbs(feeCollectorBalance, totalExpectedFees, 100, "Fee collector balance incorrect");
        
        console.log("\n--- Verification Results ---");
        console.log("First trade expected fees:", (firstExpectedMakerFee + firstExpectedTakerFee) / 1e6, "USDC");
        console.log("Second trade expected fees:", (secondExpectedMakerFee + secondExpectedTakerFee) / 1e6, "USDC");
        console.log("Total expected fees:", totalExpectedFees / 1e6, "USDC");
        console.log("Actual fees collected:", feeCollectorBalance / 1e6, "USDC");
        
        // Place a final order with Alice to check if remaining orders work
        vm.startPrank(bob);
        console.log("\n--- Bob places final market sell order ---");
        router.placeMarketOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            Price.wrap(2495e8),
            Quantity.wrap(3e18),
            Side.SELL,
            bob
        );
        vm.stopPrank();
        
        console.log("\n--- Final Balances ---");
        logBalance("Alice", alice);
        logBalance("Bob", bob);
        logBalance("Charlie", charlie);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);
    }
    
    function testCancelOrderAndRefund() public {
        console.log("\n=== CANCEL ORDER AND REFUND TEST ===");
        
        // Place buy and sell orders from different users
        vm.startPrank(alice);
        Price buyPrice = Price.wrap(2500e8);
        Quantity buyQuantity = Quantity.wrap(4e18);
        
        console.log("--- Alice places buy order ---");
        OrderId aliceOrderId = router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            buyPrice,
            buyQuantity,
            Side.BUY,
            alice
        );
        vm.stopPrank();
        
        vm.startPrank(charlie);
        Price sellPrice = Price.wrap(2520e8);
        Quantity sellQuantity = Quantity.wrap(2e18);
        
        console.log("--- Charlie places sell order ---");
        OrderId charlieOrderId = router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            sellPrice,
            sellQuantity,
            Side.SELL,
            charlie
        );
        vm.stopPrank();
        
        // Log balances after order placements
        console.log("--- Balances after order placements ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);

        PoolKey memory key = poolManager.createPoolKey(
            baseCurrency,
            quoteCurrency
        );

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        
        // Calculate locked amounts
        uint256 aliceExpectedLockedAmount = (Price.unwrap(buyPrice) * Quantity.unwrap(buyQuantity)) / 1e8;
        uint256 aliceActualLockedAmount = balanceManager.getLockedBalance(alice, address(pool.orderBook), quoteCurrency); // false = locked
        
        uint256 charlieExpectedLockedAmount = Quantity.unwrap(sellQuantity);
        uint256 charlieActualLockedAmount = balanceManager.getLockedBalance(charlie, address(pool.orderBook), baseCurrency); // false = locked
        
        assertEq(aliceActualLockedAmount, aliceExpectedLockedAmount, "Incorrect locked amount for Alice");
        assertEq(charlieActualLockedAmount, charlieExpectedLockedAmount, "Incorrect locked amount for Charlie");
        
        // Now cancel the orders
        console.log("\n--- Alice and Charlie cancel their orders ---");
        vm.startPrank(alice);
        router.cancelOrder(baseCurrency, quoteCurrency, Side.BUY, buyPrice, aliceOrderId);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        router.cancelOrder(baseCurrency, quoteCurrency, Side.BUY, buyPrice, charlieOrderId);
        vm.stopPrank();
        
        // Log balances after cancellations
        console.log("--- Balances after cancellations ---");
        logBalance("Alice", alice);
        logBalance("Charlie", charlie);
        
        // Verify locked amounts are now zero
        uint256 aliceLockedAfterCancel = balanceManager.getLockedBalance(alice, address(orderBook), quoteCurrency);
        uint256 charlieLockedAfterCancel = balanceManager.getLockedBalance(charlie, address(orderBook), baseCurrency);
        
        assertEq(aliceLockedAfterCancel, 0, "Alice's locked amount should be zero after cancel");
        assertEq(charlieLockedAfterCancel, 0, "Charlie's locked amount should be zero after cancel");
        
        // Verify available balances are refunded
        uint256 aliceAvailableAfterCancel = balanceManager.getBalance(alice, quoteCurrency);
        uint256 charlieAvailableAfterCancel = balanceManager.getBalance(charlie, baseCurrency);
        
        console.log("\n--- Verification Results ---");
        console.log("Alice order locked:", aliceExpectedLockedAmount / 1e6, "USDC");
        console.log("Alice available after cancel:", aliceAvailableAfterCancel / 1e6, "USDC");
        console.log("Charlie order locked:", charlieExpectedLockedAmount / 1e18, "WETH");
        console.log("Charlie available after cancel:", charlieAvailableAfterCancel / 1e18, "WETH");
        
        // Now David places a new order that will match with a newly placed order from Bob
        vm.startPrank(david);
        console.log("\n--- David places a buy order ---");
        router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            buyPrice,
            Quantity.wrap(3e18),
            Side.BUY,
            david
        );
        vm.stopPrank();
        
        // Bob places a matching sell order
        vm.startPrank(bob);
        console.log("--- Bob places a matching sell order ---");
        router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            buyPrice,
            Quantity.wrap(3e18),
            Side.SELL,
            bob
        );
        vm.stopPrank();
        
        // Log final balances to see successful matching
        console.log("\n--- Final Balances After New Orders and Matching ---");
        logBalance("Bob", bob);
        logBalance("David", david);
        logBalance("Fee Collector", feeCollector);
        
        // Calculate expected fees
        uint256 tradedAmount = 3e18 * 2500e8 / 1e8;
        uint256 expectedMakerFee = (tradedAmount * feeMaker) / 10000;
        uint256 expectedTakerFee = (tradedAmount * feeTaker) / 10000;
        
        // Verify fee collector received correct fees for the new trade
        uint256 feeCollectorBalance = quoteToken.balanceOf(feeCollector);
        assertApproxEqAbs(feeCollectorBalance, expectedMakerFee + expectedTakerFee, 100, "Fee collector did not receive correct fees");
    }

    // Helper function to log balances
    function logBalance(string memory user, address addr) internal view {
        console.log(user, "balances:");
        console.log("  WETH in wallet:", baseToken.balanceOf(addr) / 1e18);
        console.log("  USDC in wallet:", quoteToken.balanceOf(addr) / 1e6);
        console.log("  WETH available in contract:", balanceManager.getBalance(addr, baseCurrency) / 1e18);
        console.log("  WETH locked in contract:", balanceManager.getLockedBalance(addr, address(orderBook), baseCurrency) / 1e18);
        console.log("  USDC available in contract:", balanceManager.getBalance(addr, quoteCurrency) / 1e6);
        console.log("  USDC locked in contract:", balanceManager.getLockedBalance(addr, address(orderBook), quoteCurrency) / 1e6);
    }
}