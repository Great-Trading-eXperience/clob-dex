// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import "forge-std/Vm.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../src/interfaces/IOrderBook.sol";

contract DeployOrderbooks is Script {
    using Strings for uint256;

    address balanceManager;
    address poolManager;
    address router;
    address quoteToken;
    address quoteVault;

    address serviceManager;
    address[] orderbooks;
    address[] baseTokens;
    address[] baseVaults;

    function run() public returns (address[] memory _orderbooks, address[] memory _baseTokens) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 deployerPrivateKey2 = vm.envUint("PRIVATE_KEY_2");

        address owner = vm.addr(deployerPrivateKey);
        address owner2 = vm.addr(deployerPrivateKey2);

        baseTokens = [
            vm.envAddress("WETH_ADDRESS"),
            vm.envAddress("WBTC_ADDRESS"),
            vm.envAddress("LINK_ADDRESS"),
            vm.envAddress("UNI_ADDRESS")
        ];

        baseVaults = [
            vm.envAddress("aWETH_ADDRESS"),
            vm.envAddress("aWBTC_ADDRESS"),
            vm.envAddress("aLINK_ADDRESS"),
            vm.envAddress("aUNI_ADDRESS")
        ];

        vm.startBroadcast(deployerPrivateKey);

        balanceManager = vm.envAddress("BALANCE_MANAGER_ADDRESS");
        poolManager = vm.envAddress("POOL_MANAGER_ADDRESS");
        router = vm.envAddress("ROUTER_ADDRESS");
        quoteToken = vm.envAddress("USDC_ADDRESS");
        quoteVault = vm.envAddress("aUSDC_ADDRESS");

        // Verify contract exists
        require(
            address(PoolManager(poolManager)).code.length > 0,
            "PoolManager not deployed"
        );

        uint256 lotSize = 1e18;
        uint256 maxOrderAmount = 500e18;

        for (uint256 i = 0; i < baseTokens.length; ++i) {
            MockToken(baseTokens[i]).approve(address(balanceManager), type(uint256).max);

            Currency baseCurrency = Currency.wrap(baseTokens[i]);
            Currency quoteCurrency = Currency.wrap(quoteToken);
            PoolKey memory poolKey = PoolKey({
                baseCurrency: baseCurrency,
                quoteCurrency: quoteCurrency
            });

            address orderbook = PoolManager(poolManager).createPool(
                poolKey,
                baseVaults[i],
                quoteVault,
                lotSize,
                maxOrderAmount
            );

            orderbooks.push(orderbook);
            
            string memory baseSymbol = MockToken(baseTokens[i]).symbol();

            console.log("ORDERBOOK_%s_USDC_ADDRESS=%s", baseSymbol, orderbook);
        }

        vm.stopBroadcast();
        return (orderbooks, baseTokens);
    }
}
