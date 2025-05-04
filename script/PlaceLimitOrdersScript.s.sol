// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../script/DeployHelpers.s.sol";
import "../src/BalanceManager.sol";
import "../src/GTXRouter.sol";
import "../src/PoolManager.sol";
import "../src/mocks/MockToken.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockWETH.sol";
import "../src/resolvers/PoolManagerResolver.sol";

contract PlaceLimitOrdersScript is Script, DeployHelpers {
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    PoolManagerResolver poolManagerResolver;
    MockWETH mockWETH;
    MockUSDC mockUSDC;

    // Order parameters
    uint128 constant PRICE = 1999e6; // 1990 USDC
    uint128 constant ORDER_QUANTITY = 1e18; // 1 ETH

    function setUp() public {
        loadDeployments();
        loadContracts();
        poolManagerResolver = new PoolManagerResolver();
    }

    function loadContracts() private {
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);
        mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
        mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        // Get private keys for both users
        uint256 userAPrivateKey = getDeployerKey(); // First user
        uint256 userBPrivateKey = getDeployerKey2(); // Second user

        address userA = vm.addr(userAPrivateKey);
        address userB = vm.addr(userBPrivateKey);

        // Setup pool
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

        console.log("Order book:", address(pool.orderBook));

        //        IOrderBook orderbook = IOrderBook(address(orderBookProxy));

        // Buy first, then Sell
        placeBuyThenSell(userA, userB, pool, userAPrivateKey, userBPrivateKey);
    }

    function placeBuyThenSell(
        address userA,
        address userB,
        IPoolManager.Pool memory pool,
        uint256 userAPrivateKey,
        uint256 userBPrivateKey
    ) private {
        // Place buy order as User A
        vm.startBroadcast(userAPrivateKey);
        _setupUserFunds(userA, 0, 4000e6); // Give User A 4000 USDC for buy order
        uint48 buyOrderId = gtxRouter.placeOrderWithDeposit(pool, PRICE, ORDER_QUANTITY, IOrderBook.Side.BUY, userA);
        vm.stopBroadcast();

        // Place sell order as User B
        vm.startBroadcast(userBPrivateKey);
        _setupUserFunds(userB, 2e18, 0); // Give User B 2 ETH for sell order
        uint48 sellOrderId = gtxRouter.placeOrderWithDeposit(pool, PRICE, ORDER_QUANTITY, IOrderBook.Side.SELL, userB);
        vm.stopBroadcast();

        logOrders(buyOrderId, sellOrderId);
    }

    function placeSellThenBuy(
        address userA,
        address userB,
        IPoolManager.Pool memory pool,
        uint256 userAPrivateKey,
        uint256 userBPrivateKey
    ) private {
        // Place sell order as User A
        vm.startBroadcast(userAPrivateKey);
        _setupUserFunds(userA, 2e18, 0); // Give User A 2 ETH for sell order
        uint48 sellOrderId = gtxRouter.placeOrderWithDeposit(pool, PRICE, ORDER_QUANTITY, IOrderBook.Side.SELL, userA);
        vm.stopBroadcast();

        // Place buy order as User B
        vm.startBroadcast(userBPrivateKey);
        _setupUserFunds(userB, 0, 4000e6); // Give User B 4000 USDC for buy order
        uint48 buyOrderId = gtxRouter.placeOrderWithDeposit(pool, PRICE, ORDER_QUANTITY, IOrderBook.Side.BUY, userB);
        vm.stopBroadcast();

        logOrders(buyOrderId, sellOrderId);
    }

    function logOrders(uint48 buyOrderId, uint48 sellOrderId) private pure {
        console.log("=== Orders Placed Successfully ===");
        console.log("Buy Order ID:", buyOrderId);
        console.log("- Price:", PRICE, "USDC");
        console.log("- Quantity:", ORDER_QUANTITY, "ETH");
        console.log("\nSell Order ID:", sellOrderId);
        console.log("- Price:", PRICE, "USDC");
        console.log("- Quantity:", ORDER_QUANTITY, "ETH");
    }

    function _setupUserFunds(address user, uint256 ethAmount, uint256 usdcAmount) private {
        if (ethAmount > 0) {
            mockWETH.mint(user, ethAmount);
            IERC20(address(mockWETH)).approve(address(balanceManager), ethAmount);
        }

        if (usdcAmount > 0) {
            mockUSDC.mint(user, usdcAmount);
            IERC20(address(mockUSDC)).approve(address(balanceManager), usdcAmount);
        }
    }
}
