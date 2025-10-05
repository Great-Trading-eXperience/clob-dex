// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Script, console} from "forge-std/Script.sol";

import "../../src/core/BalanceManager.sol";
import "../../src/core/TokenRegistry.sol";
import "../../src/core/SyntheticTokenFactory.sol";
import "../../src/core/ChainRegistry.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/GTXRouter.sol";
import "../../src/core/OrderBook.sol";
import "../utils/DeployHelpers.s.sol";


/**
 * @title Deploy Core Chain Trading System
 * @dev Deploy the complete trading infrastructure on the core chain
 */
contract DeployCoreChainTrading is DeployHelpers {
    // Core chain configuration (configurable via environment)
    address public CORE_MAILBOX;
    uint32 public CORE_DOMAIN;
    string public CORE_RPC;
    string public CORE_NAME;
    
    address public SIDE_MAILBOX;
    uint32 public SIDE_DOMAIN;
    string public SIDE_RPC;
    string public SIDE_NAME;

    function run() external {
        // Load existing deployments first
        loadDeployments();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load configuration from environment
        _loadConfiguration();

        console.log("=== Deploying Core Chain Trading System ===");
        console.log("Chain ID:", block.chainid);
        console.log("Core Chain:", CORE_NAME);
        console.log("Core RPC:", CORE_RPC);
        console.log("Deployer:", deployer);
        console.log("Core Mailbox:", CORE_MAILBOX);
        console.log("Core Domain:", CORE_DOMAIN);
        console.log("Side Domain:", SIDE_DOMAIN);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy core infrastructure
        _deployTradingInfrastructure(deployer);

        vm.stopBroadcast();

        // Export deployments to JSON file
        exportDeployments();

        console.log("");
        console.log("=== Core Chain Trading Deployment Complete ===");
        console.log("[SUCCESS] Core trading system deployed");
        console.log("[SUCCESS] Ready to receive deposits from side chain");
        console.log("[SUCCESS] Ready for trading operations");
        console.log("[SUCCESS] Deployment addresses saved to deployments/%s.json", vm.toString(block.chainid));
    }

    function _loadConfiguration() internal {
        // Core chain configuration
        CORE_MAILBOX = vm.envOr("CORE_MAILBOX", 0xC9a43158891282A2B1475592D5719c001986Aaec);
        CORE_DOMAIN = uint32(vm.envOr("CORE_DOMAIN", uint256(31337)));
        
        // Handle string env vars differently
        try vm.envString("CORE_RPC") returns (string memory rpc) {
            CORE_RPC = rpc;
        } catch {
            CORE_RPC = "https://core-devnet.gtxdex.xyz";
        }
        
        try vm.envString("CORE_NAME") returns (string memory name) {
            CORE_NAME = name;
        } catch {
            CORE_NAME = "GTX Core Chain";
        }
        
        // Side chain configuration  
        SIDE_MAILBOX = vm.envOr("SIDE_MAILBOX", 0x0E801D84Fa97b50751Dbf25036d067dCf18858bF);
        SIDE_DOMAIN = uint32(vm.envOr("SIDE_DOMAIN", uint256(31338)));
        
        try vm.envString("SIDE_RPC") returns (string memory rpc) {
            SIDE_RPC = rpc;
        } catch {
            SIDE_RPC = "https://side-devnet.gtxdex.xyz";
        }
        
        try vm.envString("SIDE_NAME") returns (string memory name) {
            SIDE_NAME = name;
        } catch {
            SIDE_NAME = "GTX Side Chain";
        }
    }

    function _deployTradingInfrastructure(address owner) internal {
        console.log("=== Deploying Core Trading Components ===");

        // 1. Deploy TokenRegistry
        TokenRegistry tokenRegistryImpl = new TokenRegistry();
        console.log("TokenRegistry Implementation:", address(tokenRegistryImpl));
        deployments.push(Deployment("BEACON_TOKENREGISTRY", address(tokenRegistryImpl)));

        bytes memory tokenRegistryInitData = abi.encodeCall(tokenRegistryImpl.initialize, (owner));
        ERC1967Proxy tokenRegistryProxy = new ERC1967Proxy(address(tokenRegistryImpl), tokenRegistryInitData);
        TokenRegistry tokenRegistry = TokenRegistry(address(tokenRegistryProxy));
        console.log("TokenRegistry Proxy:", address(tokenRegistry));
        deployments.push(Deployment("PROXY_TOKENREGISTRY", address(tokenRegistry)));

        // 2. Deploy ChainRegistry
        ChainRegistry chainRegistryImpl = new ChainRegistry();
        console.log("ChainRegistry Implementation:", address(chainRegistryImpl));
        deployments.push(Deployment("BEACON_CHAINREGISTRY", address(chainRegistryImpl)));

        bytes memory chainRegistryInitData = abi.encodeCall(chainRegistryImpl.initialize, (owner));
        ERC1967Proxy chainRegistryProxy = new ERC1967Proxy(address(chainRegistryImpl), chainRegistryInitData);
        ChainRegistry chainRegistry = ChainRegistry(address(chainRegistryProxy));
        console.log("ChainRegistry Proxy:", address(chainRegistry));
        deployments.push(Deployment("PROXY_CHAINREGISTRY", address(chainRegistry)));

        // 4. Deploy BalanceManager (main trading contract)
        BalanceManager balanceManagerImpl = new BalanceManager();
        console.log("BalanceManager Implementation:", address(balanceManagerImpl));
        deployments.push(Deployment("BEACON_BALANCEMANAGER", address(balanceManagerImpl)));

        bytes memory balanceManagerInitData = abi.encodeCall(
            balanceManagerImpl.initialize,
            (
                owner, // owner
                owner, // feeReceiver
                25, // feeMaker (2.5 basis points)
                50 // feeTaker (5 basis points)
            )
        );

        ERC1967Proxy balanceManagerProxy = new ERC1967Proxy(address(balanceManagerImpl), balanceManagerInitData);
        BalanceManager balanceManager = BalanceManager(address(balanceManagerProxy));
        console.log("BalanceManager Proxy:", address(balanceManager));
        deployments.push(Deployment("PROXY_BALANCEMANAGER", address(balanceManager)));

        // 4.5. Deploy SyntheticTokenFactory (with proper proxy and initialization)
        SyntheticTokenFactory syntheticFactoryImpl = new SyntheticTokenFactory();
        console.log("SyntheticTokenFactory Implementation:", address(syntheticFactoryImpl));
        deployments.push(Deployment("BEACON_SYNTHETICTOKENFACTORY", address(syntheticFactoryImpl)));

        bytes memory syntheticFactoryInitData = abi.encodeCall(
            syntheticFactoryImpl.initialize,
            (
                owner,                  // owner
                address(tokenRegistry), // tokenRegistry
                address(balanceManager) // bridgeReceiver (BalanceManager)
            )
        );

        ERC1967Proxy syntheticFactoryProxy = new ERC1967Proxy(address(syntheticFactoryImpl), syntheticFactoryInitData);
        SyntheticTokenFactory syntheticFactory = SyntheticTokenFactory(address(syntheticFactoryProxy));
        console.log("SyntheticTokenFactory Proxy:", address(syntheticFactory));
        console.log("SyntheticTokenFactory Owner:", syntheticFactory.owner());
        deployments.push(Deployment("PROXY_SYNTHETICTOKENFACTORY", address(syntheticFactory)));

        // 5. Deploy OrderBook implementation 
        OrderBook orderBookImpl = new OrderBook();
        console.log("OrderBook Implementation:", address(orderBookImpl));
        deployments.push(Deployment("BEACON_ORDERBOOK_IMPL", address(orderBookImpl)));
        
        // 5.5. Deploy UpgradeableBeacon for OrderBook
        UpgradeableBeacon orderBookBeacon = new UpgradeableBeacon(address(orderBookImpl), owner);
        console.log("OrderBook Beacon:", address(orderBookBeacon));
        deployments.push(Deployment("BEACON_ORDERBOOK", address(orderBookBeacon)));
        
        // 6. Deploy PoolManager with correct beacon
        PoolManager poolManagerImpl = new PoolManager();
        console.log("PoolManager Implementation:", address(poolManagerImpl));
        deployments.push(Deployment("BEACON_POOLMANAGER", address(poolManagerImpl)));

        bytes memory poolManagerInitData = abi.encodeCall(
            poolManagerImpl.initialize,
            (owner, address(balanceManager), address(orderBookBeacon))
        );

        ERC1967Proxy poolManagerProxy = new ERC1967Proxy(address(poolManagerImpl), poolManagerInitData);
        PoolManager poolManager = PoolManager(address(poolManagerProxy));
        console.log("PoolManager Proxy:", address(poolManager));
        deployments.push(Deployment("PROXY_POOLMANAGER", address(poolManager)));

        // 7. Deploy GTXRouter
        GTXRouter routerImpl = new GTXRouter();
        console.log("GTXRouter Implementation:", address(routerImpl));
        deployments.push(Deployment("BEACON_ROUTER", address(routerImpl)));

        bytes memory routerInitData = abi.encodeCall(
            routerImpl.initialize,
            (address(poolManager), address(balanceManager))
        );

        ERC1967Proxy routerProxy = new ERC1967Proxy(address(routerImpl), routerInitData);
        GTXRouter router = GTXRouter(address(routerProxy));
        console.log("GTXRouter Proxy:", address(router));
        deployments.push(Deployment("PROXY_ROUTER", address(router)));

        // Configure cross-chain messaging
        _configureCrossChain(balanceManager, chainRegistry);
        
        // Configure relationships
        _configureContracts(balanceManager, poolManager, router, tokenRegistry, syntheticFactory, chainRegistry);

        console.log("");
        console.log("=== Configuration Summary ===");
        console.log("Core trading system ready for:");
        console.log("- Cross-chain deposits from side chain");
        console.log("- Synthetic token minting");
        console.log("- CLOB trading operations");
        console.log("- Pool management");
    }

    function _configureCrossChain(
        BalanceManager balanceManager,
        ChainRegistry chainRegistry
    ) internal {
        console.log("Configuring cross-chain messaging...");
        
        // Initialize cross-chain functionality on BalanceManager
        balanceManager.initializeCrossChain(CORE_MAILBOX, CORE_DOMAIN);
        console.log("[SUCCESS] BalanceManager mailbox configured:", CORE_MAILBOX);
        
        // Register local core chain in ChainRegistry
        chainRegistry.registerChain(
            CORE_DOMAIN, // chainId
            CORE_DOMAIN, // domainId
            CORE_MAILBOX, // mailbox
            CORE_RPC, // rpcEndpoint
            CORE_NAME, // name
            2000 // blockTime (2 seconds)
        );
        console.log("[SUCCESS] Core chain registered in ChainRegistry");
    }

    function _configureContracts(
        BalanceManager balanceManager,
        PoolManager poolManager,
        GTXRouter router,
        TokenRegistry tokenRegistry,
        SyntheticTokenFactory syntheticFactory,
        ChainRegistry chainRegistry
    ) internal {
        console.log("Configuring contract relationships...");

        // Set BalanceManager dependencies (following Deploy.s.sol exactly)
        balanceManager.setPoolManager(address(poolManager));
        console.log("Set PoolManager in BalanceManager");
        
        // SyntheticTokenFactory bridge receiver already set during initialization
        console.log("SyntheticTokenFactory bridge receiver set to BalanceManager during initialization");

        // Set authorizations (following Deploy.s.sol pattern)
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        console.log("Authorized PoolManager as operator in BalanceManager");
        
        balanceManager.setAuthorizedOperator(address(router), true);
        console.log("Authorized Router as operator in BalanceManager");
        
        // Set router in PoolManager  
        poolManager.setRouter(address(router));
        console.log("Set router in PoolManager");

        // Register side chain as source chain in ChainRegistry
        chainRegistry.registerChain(
            SIDE_DOMAIN, // chainId  
            SIDE_DOMAIN, // domainId
            SIDE_MAILBOX, // side chain mailbox
            SIDE_RPC, // rpcEndpoint
            SIDE_NAME, // name
            2000 // blockTime
        );

        console.log("[SUCCESS] Contract relationships configured");
        console.log("[SUCCESS] Side chain registered as source chain");
    }


}