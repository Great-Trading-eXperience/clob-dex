
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {OrderBook} from "../src/OrderBook.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {OrderId, Quantity, Side} from "../src/types/Types.sol";
import {Currency} from "../src/types/Currency.sol";
import {PoolKey} from "../src/types/Pool.sol";
import {Price} from "../src/libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {GTXRouter} from "../src/GTXRouter.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";

import {Test, console} from "forge-std/Test.sol";
import {BalanceManager} from "../src/BalanceManager.sol";
import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";

contract OrderMatchingTest is Test {
    OrderBook public orderBook;

    IOrderBook.TradingRules rules;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address david = address(0x4);

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
        baseTokenAddress = address(new MockToken("WETH", "WETH", 18));
        quoteTokenAddress = address(new MockToken("USDC", "USDC", 6));

        rules = IOrderBook.TradingRules({
            minTradeAmount: Quantity.wrap(uint128(1e14)), // 0.0001 ETH (18 decimals)
            minAmountMovement: Quantity.wrap(uint128(1e13)), // 0.00001 ETH (18 decimals)
            minOrderSize: Quantity.wrap(uint128(1e4)), // 0.01 USDC (6 decimals)
            minPriceMovement: Quantity.wrap(uint128(1e4)), // 0.01 USDC (6 decimals)
            slippageTreshold: 20 // 20%
        });

        MockToken(baseTokenAddress).mint(alice, 1_000_000_000e18);
        MockToken(baseTokenAddress).mint(bob, 1_000_000_000e18);
        MockToken(baseTokenAddress).mint(charlie, 1_000_000_000e18);
        MockToken(baseTokenAddress).mint(david, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(alice, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(bob, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(charlie, 1_000_000_000e18);
        MockToken(quoteTokenAddress).mint(david, 1_000_000_000e18);

        baseCurrency = Currency.wrap(baseTokenAddress);
        quoteCurrency = Currency.wrap(quoteTokenAddress);

        PoolKey memory poolKey = PoolKey({
            baseCurrency: Currency.wrap(baseTokenAddress),
            quoteCurrency: Currency.wrap(quoteTokenAddress)
        });


        BeaconDeployer beaconDeployer = new BeaconDeployer();

        (BeaconProxy balanceManagerProxy, address balanceManagerBeacon) = beaconDeployer.deployUpgradeableContract(
            address(new BalanceManager()),
            owner,
            abi.encodeCall(BalanceManager.initialize, (owner, owner, feeMaker, feeTaker))
        );
        balanceManager = BalanceManager(address(balanceManagerProxy));

        IBeacon orderBookBeacon = new UpgradeableBeacon(address(new OrderBook()), owner);
        address orderBookBeaconAddress = address(orderBookBeacon);

        (BeaconProxy poolManagerProxy, address poolManagerBeacon) = beaconDeployer.deployUpgradeableContract(
            address(new PoolManager()),
            owner,
            abi.encodeCall(PoolManager.initialize, (owner, address(balanceManager), address(orderBookBeaconAddress)))
        );
        poolManager = PoolManager(address(poolManagerProxy));

        (BeaconProxy routerProxy, address gtxRouterBeacon) = beaconDeployer.deployUpgradeableContract(
            address(new GTXRouter()),
            owner,
            abi.encodeCall(GTXRouter.initialize, (address(poolManager), address(balanceManager)))
        );
        router = GTXRouter(address(routerProxy));


        vm.startPrank(owner);
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
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

        vm.startPrank(charlie);
        MockToken(baseTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        MockToken(quoteTokenAddress).approve(
            address(balanceManager),
            type(uint256).max
        );
        vm.stopPrank();

        vm.startPrank(david);
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

        PoolKey memory key = poolManager.createPoolKey(
            baseCurrency,
            quoteCurrency
        );

        IPoolManager.Pool memory pool = poolManager.getPool(key);
        orderBook = OrderBook(address(pool.orderBook));
    }

    function testBasicOrderPlacement() public {
        vm.startPrank(alice);

        Price price = Price.wrap(1e8);
        Quantity quantity = Quantity.wrap(1000e6);
        Side side = Side.BUY;
        address user = alice;

        router.placeOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            price,
            quantity,
            side,
            user
        );

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            side,
            price
        );

        assertEq(orderCount, 1);
        assertEq(totalVolume, Quantity.unwrap(quantity));

        vm.stopPrank();
    }

    function testMarketOrder() public {
        vm.startPrank(alice);

        Price price = Price.wrap(1e8);
        Quantity quantity = Quantity.wrap(1000e6);
        Side side = Side.SELL;
        address user = alice;

        router.placeMarketOrderWithDeposit(
            baseCurrency,
            quoteCurrency,
            quantity,
            side,
            user
        );

        (uint48 orderCount, uint256 totalVolume) = orderBook.getOrderQueue(
            side,
            price
        );

        assertEq(totalVolume, 0);
        assertEq(orderCount, 0);

        (orderCount, totalVolume) = orderBook.getOrderQueue(side, price);

        assertEq(totalVolume, Quantity.unwrap(quantity));
        assertEq(orderCount, 1);
        vm.stopPrank();
    }
}