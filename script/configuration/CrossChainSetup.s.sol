// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {ChainRegistry} from "../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../src/core/TokenRegistry.sol";
import {SyntheticTokenFactory} from "../src/core/SyntheticTokenFactory.sol";
import {SyntheticToken} from "../src/token/SyntheticToken.sol";

/**
 * @title CrossChainSetup
 * @dev Script to deploy and configure cross-chain infrastructure
 * Deploys: ChainRegistry, TokenRegistry, SyntheticTokenFactory
 * Sets up: Espresso testnet chains, token mappings, synthetic tokens
 */
contract CrossChainSetup is Script {
    
    // Configuration
    struct DeploymentConfig {
        address owner;
        address bridgeReceiver;
        bool setupEspressoDefaults;
        bool createSyntheticTokens;
    }
    
    // Deployment results
    struct DeploymentResult {
        address chainRegistryBeacon;
        address chainRegistry;
        address tokenRegistryBeacon;
        address tokenRegistry;
        address syntheticTokenFactoryBeacon;
        address syntheticTokenFactory;
    }
    
    // Espresso testnet configuration
    struct EspressoConfig {
        uint32 rariChainId;
        uint32 rariDomainId;
        address rariMailbox;
        string rariRpc;
        
        uint32 appchainChainId;
        uint32 appchainDomainId;
        address appchainMailbox;
        string appchainRpc;
        
        uint32 arbitrumSepoliaChainId;
        uint32 arbitrumSepoliaDomainId;
        address arbitrumSepoliaMailbox;
        string arbitrumSepoliaRpc;
        
        uint32 sepoliaChainId;
        uint32 sepoliaDomainId;
        address sepoliaMailbox;
        string sepoliaRpc;
    }
    
    // Token configuration for Espresso testnet
    struct TokenConfig {
        address appchainUSDC;
        address appchainWETH;
        address appchainWBTC;
        
        address rariGsUSDC;
        address rariGsWETH;
        address rariGsWBTC;
    }
    
    function run() external {
        DeploymentConfig memory config = DeploymentConfig({
            owner: msg.sender,
            bridgeReceiver: msg.sender, // For testing - should be proper bridge contract
            setupEspressoDefaults: true,
            createSyntheticTokens: true
        });
        
        vm.startBroadcast();
        
        DeploymentResult memory result = deployInfrastructure(config);
        
        if (config.setupEspressoDefaults) {
            setupEspressoChains(result.chainRegistry);
            
            if (config.createSyntheticTokens) {
                createEspressoSyntheticTokens(result.syntheticTokenFactory);
            }
        }
        
        vm.stopBroadcast();
        
        logDeploymentResults(result);
    }
    
    /**
     * @dev Deploy all cross-chain infrastructure contracts
     */
    function deployInfrastructure(
        DeploymentConfig memory config
    ) public returns (DeploymentResult memory result) {
        console.log("Deploying cross-chain infrastructure...");
        
        // Deploy ChainRegistry
        address chainRegistryImpl = address(new ChainRegistry());
        UpgradeableBeacon chainRegistryBeacon = new UpgradeableBeacon(chainRegistryImpl, config.owner);
        BeaconProxy chainRegistryProxy = new BeaconProxy(
            address(chainRegistryBeacon),
            abi.encodeCall(ChainRegistry.initialize, (config.owner))
        );
        
        result.chainRegistryBeacon = address(chainRegistryBeacon);
        result.chainRegistry = address(chainRegistryProxy);
        
        console.log("ChainRegistry deployed at:", result.chainRegistry);
        
        // Deploy TokenRegistry
        address tokenRegistryImpl = address(new TokenRegistry());
        UpgradeableBeacon tokenRegistryBeacon = new UpgradeableBeacon(tokenRegistryImpl, config.owner);
        BeaconProxy tokenRegistryProxy = new BeaconProxy(
            address(tokenRegistryBeacon),
            abi.encodeCall(TokenRegistry.initialize, (config.owner))
        );
        
        result.tokenRegistryBeacon = address(tokenRegistryBeacon);
        result.tokenRegistry = address(tokenRegistryProxy);
        
        console.log("TokenRegistry deployed at:", result.tokenRegistry);
        
        // Deploy SyntheticTokenFactory
        address syntheticTokenFactoryImpl = address(new SyntheticTokenFactory());
        UpgradeableBeacon syntheticTokenFactoryBeacon = new UpgradeableBeacon(syntheticTokenFactoryImpl, config.owner);
        BeaconProxy syntheticTokenFactoryProxy = new BeaconProxy(
            address(syntheticTokenFactoryBeacon),
            abi.encodeCall(SyntheticTokenFactory.initialize, (
                config.owner,
                result.tokenRegistry,
                config.bridgeReceiver
            ))
        );
        
        result.syntheticTokenFactoryBeacon = address(syntheticTokenFactoryBeacon);
        result.syntheticTokenFactory = address(syntheticTokenFactoryProxy);
        
        console.log("SyntheticTokenFactory deployed at:", result.syntheticTokenFactory);
        
        // Transfer TokenRegistry ownership to SyntheticTokenFactory for automated registration
        TokenRegistry(result.tokenRegistry).transferOwnership(result.syntheticTokenFactory);
        console.log("TokenRegistry ownership transferred to SyntheticTokenFactory");
        
        return result;
    }
    
    /**
     * @dev Setup Espresso testnet chains in ChainRegistry
     */
    function setupEspressoChains(address chainRegistryAddress) public {
        console.log("Setting up Espresso testnet chains...");
        
        ChainRegistry chainRegistry = ChainRegistry(chainRegistryAddress);
        EspressoConfig memory espresso = getEspressoConfig();
        
        // Register Rari Testnet (if not already registered)
        try chainRegistry.getChainConfig(espresso.rariChainId) {
            console.log("Rari Testnet already registered");
        } catch {
            chainRegistry.registerChain(
                espresso.rariChainId,
                espresso.rariDomainId,
                espresso.rariMailbox,
                espresso.rariRpc,
                "Rari Testnet",
                2  // 2 second block time
            );
            console.log("Rari Testnet registered");
        }
        
        // Register Appchain Testnet (if not already registered)
        try chainRegistry.getChainConfig(espresso.appchainChainId) {
            console.log("Appchain Testnet already registered");
        } catch {
            chainRegistry.registerChain(
                espresso.appchainChainId,
                espresso.appchainDomainId,
                espresso.appchainMailbox,
                espresso.appchainRpc,
                "Appchain Testnet",
                2  // 2 second block time
            );
            console.log("Appchain Testnet registered");
        }
        
        // Register Arbitrum Sepolia (if not already registered)
        try chainRegistry.getChainConfig(espresso.arbitrumSepoliaChainId) {
            console.log("Arbitrum Sepolia already registered");
        } catch {
            chainRegistry.registerChain(
                espresso.arbitrumSepoliaChainId,
                espresso.arbitrumSepoliaDomainId,
                espresso.arbitrumSepoliaMailbox,
                espresso.arbitrumSepoliaRpc,
                "Arbitrum Sepolia",
                1  // 1 second block time
            );
            console.log("Arbitrum Sepolia registered");
        }
        
        // Register Ethereum Sepolia (if not already registered)
        try chainRegistry.getChainConfig(espresso.sepoliaChainId) {
            console.log("Ethereum Sepolia already registered");
        } catch {
            chainRegistry.registerChain(
                espresso.sepoliaChainId,
                espresso.sepoliaDomainId,
                espresso.sepoliaMailbox,
                espresso.sepoliaRpc,
                "Ethereum Sepolia",
                12  // 12 second block time
            );
            console.log("Ethereum Sepolia registered");
        }
    }
    
    /**
     * @dev Create synthetic tokens for Espresso testnet
     */
    function createEspressoSyntheticTokens(address factoryAddress) public {
        console.log("Creating Espresso testnet synthetic tokens...");
        
        SyntheticTokenFactory factory = SyntheticTokenFactory(factoryAddress);
        TokenConfig memory tokens = getTokenConfig();
        EspressoConfig memory espresso = getEspressoConfig();
        
        // Create synthetic USDC (Appchain -> Rari)
        try factory.getSyntheticToken(espresso.appchainChainId, tokens.appchainUSDC) returns (address existing) {
            if (existing != address(0)) {
                console.log("Synthetic USDC already exists at:", existing);
            } else {
                createSyntheticToken(factory, espresso, tokens, "USDC");
            }
        } catch {
            createSyntheticToken(factory, espresso, tokens, "USDC");
        }
        
        // Create synthetic WETH (Appchain -> Rari)
        try factory.getSyntheticToken(espresso.appchainChainId, tokens.appchainWETH) returns (address existing) {
            if (existing != address(0)) {
                console.log("Synthetic WETH already exists at:", existing);
            } else {
                createSyntheticToken(factory, espresso, tokens, "WETH");
            }
        } catch {
            createSyntheticToken(factory, espresso, tokens, "WETH");
        }
        
        // Create synthetic WBTC (Appchain -> Rari)
        try factory.getSyntheticToken(espresso.appchainChainId, tokens.appchainWBTC) returns (address existing) {
            if (existing != address(0)) {
                console.log("Synthetic WBTC already exists at:", existing);
            } else {
                createSyntheticToken(factory, espresso, tokens, "WBTC");
            }
        } catch {
            createSyntheticToken(factory, espresso, tokens, "WBTC");
        }
    }
    
    /**
     * @dev Helper function to create individual synthetic tokens
     */
    function createSyntheticToken(
        SyntheticTokenFactory factory,
        EspressoConfig memory espresso,
        TokenConfig memory tokens,
        string memory tokenType
    ) internal {
        if (keccak256(bytes(tokenType)) == keccak256(bytes("USDC"))) {
            address synthetiUSDC = factory.createSyntheticToken(
                espresso.appchainChainId,
                tokens.appchainUSDC,
                espresso.rariChainId,
                "Green Synthetic USDC",
                "gsUSDC",
                6,  // USDC decimals
                6   // Keep same decimals for USDC
            );
            console.log("Synthetic USDC created at:", synthetiUSDC);
        } else if (keccak256(bytes(tokenType)) == keccak256(bytes("WETH"))) {
            address synthetiWETH = factory.createSyntheticToken(
                espresso.appchainChainId,
                tokens.appchainWETH,
                espresso.rariChainId,
                "Green Synthetic WETH",
                "gsWETH",
                18, // WETH decimals
                18  // Keep same decimals for WETH
            );
            console.log("Synthetic WETH created at:", synthetiWETH);
        } else if (keccak256(bytes(tokenType)) == keccak256(bytes("WBTC"))) {
            address synthetiWBTC = factory.createSyntheticToken(
                espresso.appchainChainId,
                tokens.appchainWBTC,
                espresso.rariChainId,
                "Green Synthetic WBTC",
                "gsWBTC",
                8,  // WBTC decimals
                8   // Keep same decimals for WBTC
            );
            console.log("Synthetic WBTC created at:", synthetiWBTC);
        }
    }
    
    /**
     * @dev Get Espresso testnet configuration
     */
    function getEspressoConfig() internal pure returns (EspressoConfig memory) {
        return EspressoConfig({
            rariChainId: 1918988905,
            rariDomainId: 1918988905,
            rariMailbox: 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358,
            rariRpc: "https://rari.caff.testnet.espresso.network",
            
            appchainChainId: 4661,
            appchainDomainId: 4661,
            appchainMailbox: 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1,
            appchainRpc: "https://appchain.caff.testnet.espresso.network",
            
            arbitrumSepoliaChainId: 421614,
            arbitrumSepoliaDomainId: 421614,
            arbitrumSepoliaMailbox: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766,
            arbitrumSepoliaRpc: "https://arb-sepolia.g.alchemy.com/v2/your-api-key",
            
            sepoliaChainId: 11155111,
            sepoliaDomainId: 11155111,
            sepoliaMailbox: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766,
            sepoliaRpc: "https://eth-sepolia.g.alchemy.com/v2/your-api-key"
        });
    }
    
    /**
     * @dev Get token addresses for Espresso testnet
     */
    function getTokenConfig() internal pure returns (TokenConfig memory) {
        return TokenConfig({
            // Appchain testnet tokens
            appchainUSDC: 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516,
            appchainWETH: 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F,
            appchainWBTC: 0xb2e9Eabb827b78e2aC66bE17327603778D117d18,
            
            // Rari testnet synthetic tokens (will be created by factory)
            rariGsUSDC: 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68,
            rariGsWETH: 0xC7A1777e80982E01e07406e6C6E8B30F5968F836,
            rariGsWBTC: 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF
        });
    }
    
    /**
     * @dev Log deployment results
     */
    function logDeploymentResults(DeploymentResult memory result) internal view {
        console.log("\n=== CROSS-CHAIN INFRASTRUCTURE DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("ChainRegistry:");
        console.log("  Beacon:", result.chainRegistryBeacon);
        console.log("  Proxy:", result.chainRegistry);
        console.log("");
        console.log("TokenRegistry:");
        console.log("  Beacon:", result.tokenRegistryBeacon);
        console.log("  Proxy:", result.tokenRegistry);
        console.log("");
        console.log("SyntheticTokenFactory:");
        console.log("  Beacon:", result.syntheticTokenFactoryBeacon);
        console.log("  Proxy:", result.syntheticTokenFactory);
        console.log("");
        console.log("Next steps:");
        console.log("1. Configure bridge receiver contract address");
        console.log("2. Set up cross-chain message handlers");
        console.log("3. Test cross-chain token transfers");
        console.log("4. Monitor and manage synthetic token supply");
        console.log("");
    }
}