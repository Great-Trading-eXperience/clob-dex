// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {BalanceManager} from "@gtxcore/BalanceManager.sol";
import "@gtxcore/interfaces/IOrderBook.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {Currency} from "@gtxcore/libraries/Currency.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {MockToken} from "@gtx/mocks/MockToken.sol";
import {GTXRouter} from "@gtxcore/GTXRouter.sol";
import {OrderBook} from "@gtxcore/OrderBook.sol";
import {IPoolManager} from "@gtxcore/interfaces/IPoolManager.sol";

import {PoolKey} from "@gtxcore/libraries/Pool.sol";

import {PoolManager} from "@gtxcore/PoolManager.sol";
import {Test, console} from "forge-std/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract MarketOrderQuantityValidationTest is Test {
    OrderBook public orderBook;

    IOrderBook.TradingRules rules;

    address alice = address(0x1);
    address bob = address(0x2);

    address owner = address(0x5);

    address baseTokenAddress;
    address quoteTokenAddress;

    Currency baseCurrency;
    Currency quoteCurrency;

    uint256 feeMaker = 1; // Example fee maker value
    uint256 feeTaker = 1; // Example fee taker value
    uint256 lotSize = 1e18; // Example lot size
    uint256 maxOrderAmount = 500e18; // Example max order amount

    GTXRouter router;
    PoolManager poolManager;
    BalanceManager balanceManager;

    function setUp() public {
        baseTokenAddress = address(new MockToken("ETH", "ETH", 18));
        quoteTokenAddress = address(new MockToken("USDC", "USDC", 6));

        rules = IOrderBook.TradingRules({
            minTradeAmount: 1e14, // 0.0001 ETH (18 decimals)
            minAmountMovement: 1e13, // 0.00001 ETH (18 decimals)
            minOrderSize: 1e4, // 0.01 USDC (6 decimals)
            minPriceMovement: 1e4 // 0.01 USDC (6 decimals)
        });

        MockToken(baseTokenAddress).mint(alice, 100e18);
        MockToken(baseTokenAddress).mint(bob, 100e18);
        MockToken(quoteTokenAddress).mint(alice, 100_000e6);
        MockToken(quoteTokenAddress).mint(bob, 100_000e6);

        baseCurrency = Currency.wrap(baseTokenAddress);
        quoteCurrency = Currency.wrap(quoteTokenAddress);

        PoolKey memory key = PoolKey({
            baseCurrency: Currency.wrap(baseTokenAddress),
            quoteCurrency: Currency.wrap(quoteTokenAddress)
        });

        BeaconDeployer beaconDeployer = new BeaconDeployer();

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

        IBeacon orderBookBeacon = new UpgradeableBeacon(
            address(new OrderBook()),
            owner
        );
        address orderBookBeaconAddress = address(orderBookBeacon);

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

        (BeaconProxy routerProxy, ) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(
                GTXRouter.initialize,
                (address(poolManager), address(balanceManager))
            )
        );
        router = GTXRouter(address(routerProxy));

        vm.startPrank(owner);
        balanceManager.setPoolManager(address(poolManager));
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.setAuthorizedOperator(address(routerProxy), true);
        poolManager.setRouter(address(router));
        vm.stopPrank();

        vm.startPrank(alice);
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(bob);
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();


        poolManager.createPool(baseCurrency, quoteCurrency, rules);

        key = poolManager.createPoolKey(baseCurrency, quoteCurrency);

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderBook = OrderBook(address(pool.orderBook));
    }

    function testSimpleMarketOrder() public {
        IPoolManager.Pool memory pool = _getPool(baseCurrency, quoteCurrency);
        
        // Record initial balances
        uint256 aliceInitialETH = MockToken(baseTokenAddress).balanceOf(alice);
        uint256 aliceInitialUSDC = MockToken(quoteTokenAddress).balanceOf(alice);
        uint256 bobInitialETH = MockToken(baseTokenAddress).balanceOf(bob);
        uint256 bobInitialUSDC = MockToken(quoteTokenAddress).balanceOf(bob);
        
        // Alice sells 4 ETH at 2000 USD each
        vm.startPrank(alice);
        router.placeLimitOrder(
            pool,
            2000e6,
            4e18,
            IOrderBook.Side.SELL,
            IOrderBook.TimeInForce.GTC,
            4e18
        );
        vm.stopPrank();

        // Bob buys with 2000 USD (should get 1 ETH)
        vm.startPrank(bob);
        // uint128 minOutAmount = router.calculateMinOutAmountForMarket(
        //     pool,
        //     2000e6,
        //     IOrderBook.Side.BUY,
        //     500
        // );
        
        router.placeMarketOrder(
            pool,
            1e18,
            IOrderBook.Side.BUY,
            2000e6,
            0
        );
        vm.stopPrank();
        
        // Verify order book state: 3 ETH remaining
        (, uint256 remainingVolume) = orderBook.getOrderQueue(IOrderBook.Side.SELL, 2000e6);
        assertEq(remainingVolume, 3e18, "Should have 3 ETH remaining in sell order");
        
        // Check balance manager balances (internal balances after trade)
        uint256 aliceETHBalance = balanceManager.getBalance(alice, baseCurrency);
        uint256 aliceUSDCBalance = balanceManager.getBalance(alice, quoteCurrency);
        uint256 bobETHBalance = balanceManager.getBalance(bob, baseCurrency);
        uint256 bobUSDCBalance = balanceManager.getBalance(bob, quoteCurrency);
        
        console.log("Alice ETH balance in BalanceManager:", aliceETHBalance);
        console.log("Alice USDC balance in BalanceManager:", aliceUSDCBalance);
        console.log("Bob ETH balance in BalanceManager:", bobETHBalance);
        console.log("Bob USDC balance in BalanceManager:", bobUSDCBalance);
        
        // Verify order book state
        assertEq(remainingVolume, 3e18, "Should have 3 ETH remaining in sell order");
        
        // Verify current best price is still 2000 USDC (the remaining order)
        IOrderBook.PriceVolume memory bestPriceVolume = orderBook.getBestPrice(IOrderBook.Side.SELL);
        assertEq(bestPriceVolume.price, 2000e6, "Best sell price should still be 2000 USDC");
        assertEq(bestPriceVolume.volume, 3e18, "Best sell volume should be 3 ETH remaining");
        
        // Verify balance changes with fees
        assertEq(aliceUSDCBalance, 1998e6, "Alice should have received 2000 USDC minus 2 USDC fee");
        assertEq(bobETHBalance, 999e15, "Bob should have 0.999 ETH in balance manager (1 ETH minus 0.001 ETH fee)");
    }


    function _getPool(
        Currency currency1,
        Currency currency2
    ) internal view returns (IPoolManager.Pool memory pool) {
        IPoolManager _poolManager = IPoolManager(poolManager);
        PoolKey memory key = _poolManager.createPoolKey(currency1, currency2);

        return _poolManager.getPool(key);
    }
}