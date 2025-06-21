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

contract PlaceMarketMockOrderBook is Script, DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";

    // Core contracts
    BalanceManager balanceManager;
    PoolManager poolManager;
    GTXRouter gtxRouter;
    PoolManagerResolver poolManagerResolver;

    // Mock tokens
    MockWETH mockWETH;
    MockUSDC mockUSDC;

    // Track order IDs for verification
    uint48[] marketBuyOrderIds;
    uint48[] marketSellOrderIds;

    // Deployer address
    address deployerAddress;

    function setUp() public {
        loadDeployments();
        loadContracts();

        // Deploy the resolver
        poolManagerResolver = new PoolManagerResolver();
    }

    function loadContracts() private {
        // Load core contracts
        balanceManager = BalanceManager(deployed[BALANCE_MANAGER_ADDRESS].addr);
        poolManager = PoolManager(deployed[POOL_MANAGER_ADDRESS].addr);
        gtxRouter = GTXRouter(deployed[GTX_ROUTER_ADDRESS].addr);

        // Load mock tokens
        mockWETH = MockWETH(deployed[WETH_ADDRESS].addr);
        mockUSDC = MockUSDC(deployed[USDC_ADDRESS].addr);
    }

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey2();
        vm.startBroadcast(deployerPrivateKey);

        deployerAddress = vm.addr(deployerPrivateKey);
        
        placeMarketOrdersETHUSDC();
        verifyMarketOrders();

        vm.stopBroadcast();
    }

    function placeMarketOrdersETHUSDC() private {
        console.log("\n=== Placing Market Orders on ETH/USDC ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));

        // Get the pool using the resolver
        IPoolManager.Pool memory pool = poolManagerResolver.getPool(weth, usdc, address(poolManager));

        // Setup sender with funds for market orders
        _setupFunds(50e18, 100_000e6); // 50 ETH, 100,000 USDC


        // Check current approvals
        uint256 wethAllowance = IERC20(address(mockWETH)).allowance(deployerAddress, address(balanceManager));
        uint256 usdcAllowance = IERC20(address(mockUSDC)).allowance(deployerAddress, address(balanceManager));
        
        console.log("\nCurrent allowances:");
        console.log("WETH allowance:", wethAllowance);
        console.log("USDC allowance:", usdcAllowance);

        if (wethAllowance < 5e18) {
            console.log("Approving WETH for balance manager");
            return;
        }

        if (usdcAllowance < 1e6) {
            console.log("Approving USDC for balance manager");
            return;
        }

        // Place market BUY orders (buys ETH with USDC)
        // These will execute against the SELL limit orders
        _placeMarketBuyOrders(pool, 1); // 5 buy orders

        // Place market SELL orders (sells ETH for USDC)
        // These will execute against the BUY limit orders
        _placeMarketSellOrders(pool, 1); // 5 sell orders

        // Print summary
        console.log("\nMarket orders placed:");
        console.log("- 5 market BUY orders (buying ETH with USDC)");
        console.log("- 5 market SELL orders (selling ETH for USDC)");
    }

    function _setupFunds(uint256 ethAmount, uint256 usdcAmount) private {
        // Mint tokens directly to sender
        mockWETH.mint(deployerAddress, ethAmount);
        mockUSDC.mint(deployerAddress, usdcAmount);

        // Approve tokens for balance manager
        bool result = IERC20(address(mockWETH)).approve(address(balanceManager), type(uint256).max);
        console.log("Approved WETH for balance manager:", result);
        console.log("WETH allowance:", IERC20(address(mockWETH)).allowance(deployerAddress, address(balanceManager)));
        result = IERC20(address(mockUSDC)).approve(address(balanceManager), type(uint256).max);
        console.log("Approved USDC for balance manager:", result);
        console.log("USDC allowance:", IERC20(address(mockUSDC)).allowance(deployerAddress, address(balanceManager)));
    }

    function _placeMarketBuyOrders(
        IPoolManager.Pool memory pool,
        uint8 numOrders
    ) private {
        console.log("\n--- Placing Market BUY Orders ---");
        
        // Different quantities for variety
        uint128[] memory quantities = new uint128[](5);
        quantities[0] = 1e17;  // 0.1 ETH
        quantities[1] = 2e17;  // 0.2 ETH
        quantities[2] = 5e17;  // 0.5 ETH
        quantities[3] = 1e18;  // 1.0 ETH
        quantities[4] = 2e18;  // 2.0 ETH

        for (uint8 i = 0; i < numOrders; i++) {
            // Market orders typically use 0 for price
            uint48 orderId = gtxRouter.placeMarketOrderWithDeposit(
                pool, 
                quantities[i % 5], 
                IOrderBook.Side.BUY
            );
            
            console.log("Placed market BUY order ID:", orderId);
            console.log("Quantity:", quantities[i % 5], "ETH");
            marketBuyOrderIds.push(orderId);
        }
    }

    function _placeMarketSellOrders(
        IPoolManager.Pool memory pool,
        uint8 numOrders
    ) private {
        console.log("\n--- Placing Market SELL Orders ---");
        
        // Different quantities for variety
        uint128[] memory quantities = new uint128[](5);
        quantities[0] = 1e17;  // 0.1 ETH
        quantities[1] = 2e17;  // 0.2 ETH
        quantities[2] = 5e17;  // 0.5 ETH
        quantities[3] = 1e18;  // 1.0 ETH
        quantities[4] = 2e18;  // 2.0 ETH

        for (uint8 i = 0; i < numOrders; i++) {
            // Market orders typically use 0 for price
            uint48 orderId = gtxRouter.placeMarketOrderWithDeposit(
                pool, 
                quantities[i % 5], 
                IOrderBook.Side.SELL
            );
            
            console.log("Placed market SELL order ID:", orderId);
            console.log("Quantity:", quantities[i % 5], "ETH");
            marketSellOrderIds.push(orderId);
        }
    }

    function verifyMarketOrders() private {
        console.log("\n=== Verifying Market Orders ===");

        // Get currency objects
        Currency weth = Currency.wrap(address(mockWETH));
        Currency usdc = Currency.wrap(address(mockUSDC));

        // Check market buy orders
        console.log("\n--- Market BUY Orders ---");
        for (uint256 i = 0; i < marketBuyOrderIds.length; i++) {
            _checkOrderDetails(weth, usdc, marketBuyOrderIds[i], string(abi.encodePacked("Market BUY #", uint2str(i + 1))));
        }

        // Check market sell orders
        console.log("\n--- Market SELL Orders ---");
        for (uint256 i = 0; i < marketSellOrderIds.length; i++) {
            _checkOrderDetails(weth, usdc, marketSellOrderIds[i], string(abi.encodePacked("Market SELL #", uint2str(i + 1))));
        }

        // Check orderbook state after market orders
        console.log("\n--- Order Book State After Market Orders ---");
        
        // Check best prices
        IOrderBook.PriceVolume memory bestBuy = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.BUY);
        IOrderBook.PriceVolume memory bestSell = gtxRouter.getBestPrice(weth, usdc, IOrderBook.Side.SELL);

        console.log("Best BUY price:", bestBuy.price, "USDC");
        console.log("Volume at best BUY:", bestBuy.volume, "ETH\n");

        console.log("Best SELL price:", bestSell.price, "USDC");
        console.log("Volume at best SELL:", bestSell.volume, "ETH\n");

        // Check balance changes
        _checkBalances();
    }

    function _checkOrderDetails(Currency base, Currency quote, uint48 orderId, string memory label) private {
        IOrderBook.Order memory order = gtxRouter.getOrder(base, quote, orderId);

        console.log("\nOrder details for", label);
        console.log("Order ID:", orderId);
        console.log("User:", order.user);
        console.log("Side:", order.side == IOrderBook.Side.BUY ? "BUY" : "SELL");
        console.log("Type:", order.orderType == IOrderBook.OrderType.LIMIT ? "LIMIT" : "MARKET");
        console.log("Price:", order.price, "USDC");
        console.log("Quantity:", order.quantity, "ETH");
        console.log("Filled:", order.filled, "ETH");
        console.log("---");
    }

    function _checkBalances() private {
        console.log("\n--- Balance Check ---");
        
        // Check sender's balances
        uint256 ethBalance = mockWETH.balanceOf(deployerAddress);
        uint256 usdcBalance = mockUSDC.balanceOf(deployerAddress);
        
        console.log("Sender ETH balance:", ethBalance, "wei");
        console.log("Sender USDC balance:", usdcBalance, "units");
        
        // Check balance manager balances
        uint256 bmEthBalance = mockWETH.balanceOf(address(balanceManager));
        uint256 bmUsdcBalance = mockUSDC.balanceOf(address(balanceManager));
        
        console.log("BalanceManager ETH balance:", bmEthBalance, "wei");
        console.log("BalanceManager USDC balance:", bmUsdcBalance, "units");
    }

    // Utility function to convert uint to string
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}