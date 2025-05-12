//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import {VotingEscrowMainchain} from "../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {VotingControllerUpg} from "../src/incentives/voting-controller/VotingControllerUpg.sol";
import {GaugeControllerMainchainUpg} from
    "../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import {GTXMarketMakerFactory} from "../src/marketmaker/GTXMarketMakerFactory.sol";
import {GTXMarketMakerVault} from "../src/marketmaker/GTXMarketMakerVault.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BalanceManager} from "../src/BalanceManager.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {GTXRouter} from "../src/GTXRouter.sol";
import {OrderBook} from "../src/OrderBook.sol";

contract DeployGauge is Script {
    uint256 deployerPrivateKey;
    address owner;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock token for incentives
        MockToken token = new MockToken("Test Token", "TEST", 18);

        // Deploy GTX infrastructure
        
        // 1. Balance Manager
        BalanceManager balanceManager = new BalanceManager();
        balanceManager.initialize(owner, owner, 20, 30); // 0.2% maker fee, 0.3% taker fee
        
        // 2. OrderBook Beacon
        OrderBook orderBookImpl = new OrderBook();
        UpgradeableBeacon orderBookBeacon = new UpgradeableBeacon(address(orderBookImpl), owner);
        
        // 3. Pool Manager
        PoolManager poolManager = new PoolManager();
        poolManager.initialize(owner, address(balanceManager), address(orderBookBeacon));
        
        // 4. Router
        GTXRouter router = new GTXRouter();
        router.initialize(owner, address(poolManager));
        
        // Set router in pool manager
        poolManager.setRouter(address(router));

        // Deploy voting escrow
        VotingEscrowMainchain votingEscrow =
            new VotingEscrowMainchain(address(token), address(0), 1e6);

        // Deploy voting controller
        address votingControllerImp =
            address(new VotingControllerUpg(address(votingEscrow), address(0)));
        VotingControllerUpg votingController = VotingControllerUpg(
            address(
                new TransparentUpgradeableProxy(
                    votingControllerImp,
                    owner,
                    abi.encodeWithSelector(VotingControllerUpg.initialize.selector, 100_000)
                )
            )
        );

        // Deploy market maker vault implementation
        GTXMarketMakerVault vaultImplementation = new GTXMarketMakerVault();
        
        // Deploy market maker factory
        GTXMarketMakerFactory marketMakerFactory = new GTXMarketMakerFactory();
        marketMakerFactory.initialize(
            owner,
            address(votingEscrow),
            address(0), // Will set gauge controller later
            address(router),
            address(poolManager),
            address(balanceManager),
            address(vaultImplementation)
        );

        // Deploy gauge controller
        address gaugeControllerImp = address(
            new GaugeControllerMainchainUpg(
                address(votingController), address(token), address(marketMakerFactory)
            )
        );
        GaugeControllerMainchainUpg gaugeController = GaugeControllerMainchainUpg(
            address(
                new TransparentUpgradeableProxy(
                    gaugeControllerImp,
                    owner,
                    abi.encodeWithSelector(GaugeControllerMainchainUpg.initialize.selector)
                )
            )
        );

        // Update factory with gauge controller
        marketMakerFactory.updateGaugeAddresses(address(votingEscrow), address(gaugeController));
        
        // Set parameter constraints
        marketMakerFactory.updateParameterConstraints(
            1000,   // minTargetRatio (10%)
            9000,   // maxTargetRatio (90%)
            5,      // minSpread (0.05%)
            500,    // maxSpread (5%)
            0.01 * 10**18, // minOrderSize
            100 * 10**18,  // maxOrderSize
            10,     // minSlippageTolerance (0.1%)
            200,    // maxSlippageTolerance (2%)
            2,      // minActiveOrders
            100,    // maxActiveOrders
            5 minutes, // minRebalanceInterval
            7 days     // maxRebalanceInterval
        );

        vm.stopBroadcast();

        console.log("Infrastructure:");
        console.log("BalanceManager deployed at", address(balanceManager));
        console.log("OrderBook implementation deployed at", address(orderBookImpl));
        console.log("OrderBook beacon deployed at", address(orderBookBeacon));
        console.log("PoolManager deployed at", address(poolManager));
        console.log("GTXRouter deployed at", address(router));
        
        console.log("\nIncentives:");
        console.log("VotingEscrowMainchain deployed at", address(votingEscrow));
        console.log("VotingControllerUpg deployed at", address(votingController));
        console.log("GaugeControllerMainchainUpg deployed at", address(gaugeController));
        
        console.log("\nMarket Maker:");
        console.log("GTXMarketMakerVault implementation deployed at", address(vaultImplementation));
        console.log("GTXMarketMakerFactory deployed at", address(marketMakerFactory));

        // Display the beacon address from the factory for verification
        address vaultBeacon = marketMakerFactory.getVaultBeacon();
        console.log("Vault Beacon deployed at", vaultBeacon);
    }
}