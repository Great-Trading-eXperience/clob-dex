// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../src/core/PoolManager.sol";
import "../../src/core/TokenRegistry.sol";
import "../../src/core/SyntheticTokenFactory.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title MockERC20
 * @dev Enhanced mock ERC20 token for core chain testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title Deploy Core Chain Tokens
 * @dev Deploy native tokens and synthetic tokens on the core chain
 * Usage: make deploy-core-chain-tokens network=gtx_core_devnet
 * Note: Trading pools should be created separately using dedicated pool creation script
 */
contract DeployCoreChainTokens is DeployHelpers {
    
    // Core chain contracts (loaded from deployments)
    PoolManager poolManager;
    TokenRegistry tokenRegistry;
    SyntheticTokenFactory syntheticFactory;
    
    // Token information
    struct TokenInfo {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply;
        address tokenAddress;
        address syntheticAddress;
    }
    
    TokenInfo[] public nativeTokens;
    TokenInfo[] public syntheticTokens;
    
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Load core chain deployments
        loadDeployments();
        _loadCoreContracts();
        
        console.log("========== DEPLOYING CORE CHAIN TOKENS ==========");

        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy native tokens on core chain
        _deployNativeTokens();
        
        // Step 2: Deploy synthetic tokens (for side chain assets)
        _deploySyntheticTokens();
        
        vm.stopBroadcast();
        
        // Export deployments to JSON
        exportDeployments();
        
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Deployment addresses saved to JSON file:");
        _printDeployedTokens();
    }
    
    function _loadCoreContracts() internal {
        // Load core chain contracts from deployments with env var fallbacks
        string memory poolManagerKey = vm.envOr("POOL_MANAGER_KEY", string("PROXY_POOLMANAGER"));
        string memory tokenRegistryKey = vm.envOr("TOKEN_REGISTRY_KEY", string("PROXY_TOKENREGISTRY"));
        string memory syntheticFactoryKey = vm.envOr("SYNTHETIC_FACTORY_KEY", string("PROXY_SYNTHETICTOKENFACTORY"));
        
        require(deployed[poolManagerKey].isSet, "PoolManager not deployed");
        require(deployed[tokenRegistryKey].isSet, "TokenRegistry not deployed");
        require(deployed[syntheticFactoryKey].isSet, "SyntheticTokenFactory not deployed");
        
        poolManager = PoolManager(deployed[poolManagerKey].addr);
        tokenRegistry = TokenRegistry(deployed[tokenRegistryKey].addr);
        syntheticFactory = SyntheticTokenFactory(deployed[syntheticFactoryKey].addr);
    }
    
    function _deployNativeTokens() internal {
        // Initialize native token configurations
        nativeTokens.push(TokenInfo({
            name: "Core USDC",
            symbol: "USDC",
            decimals: 6,
            initialSupply: 10000000 * 10**6, // 10M USDC
            tokenAddress: address(0),
            syntheticAddress: address(0)
        }));
        
        nativeTokens.push(TokenInfo({
            name: "Core WETH",
            symbol: "WETH",
            decimals: 18,
            initialSupply: 100000 * 10**18, // 100K WETH
            tokenAddress: address(0),
            syntheticAddress: address(0)
        }));
        
        nativeTokens.push(TokenInfo({
            name: "Core WBTC",
            symbol: "WBTC",
            decimals: 8,
            initialSupply: 10000 * 10**8, // 10K WBTC
            tokenAddress: address(0),
            syntheticAddress: address(0)
        }));
        
        // Deploy all native tokens
        for (uint256 i = 0; i < nativeTokens.length; i++) {
            TokenInfo storage token = nativeTokens[i];
            
            MockERC20 mockToken = new MockERC20(
                token.name,
                token.symbol,
                token.decimals,
                token.initialSupply
            );
            
            token.tokenAddress = address(mockToken);
            
            // Save to deployments with deployed mapping
            deployments.push(Deployment(token.symbol, token.tokenAddress));
            deployed[token.symbol] = DeployedContract(token.tokenAddress, true);
        }
    }
    
    function _deploySyntheticTokens() internal {
        // Load side chain token addresses from side chain deployment file
        string memory sideChainName;
        try vm.envString("SIDE_CHAIN") returns (string memory chain) {
            sideChainName = chain;
        } catch {
            sideChainName = "31338";
        }
        uint32 sideChainId = uint32(vm.envOr("SIDE_CHAIN_ID", uint256(31338)));
        
        string memory sideDeploymentPath = string.concat(
            vm.projectRoot(), 
            "/deployments/", 
            sideChainName, 
            ".json"
        );
        
        if (!_fileExists(sideDeploymentPath)) {
            console.log("Side chain deployment not found: %s", sideDeploymentPath);
            revert(string.concat("Side chain deployment not found: ", sideDeploymentPath));
        }
        
        string memory sideJson = vm.readFile(sideDeploymentPath);
        address sideUSDC = vm.parseJsonAddress(sideJson, ".USDC");
        address sideWETH = vm.parseJsonAddress(sideJson, ".WETH");
        address sideWBTC = vm.parseJsonAddress(sideJson, ".WBTC");
        
        // Initialize synthetic token configurations
        syntheticTokens.push(TokenInfo({
            name: "GTX Synthetic USDC",
            symbol: "gsUSDC",
            decimals: 6,
            initialSupply: 0, // Synthetic tokens don't have initial supply
            tokenAddress: sideUSDC,
            syntheticAddress: address(0)
        }));
        
        syntheticTokens.push(TokenInfo({
            name: "GTX Synthetic WETH",
            symbol: "gsWETH",
            decimals: 18,
            initialSupply: 0,
            tokenAddress: sideWETH,
            syntheticAddress: address(0)
        }));
        
        syntheticTokens.push(TokenInfo({
            name: "GTX Synthetic WBTC",
            symbol: "gsWBTC",
            decimals: 8,
            initialSupply: 0,
            tokenAddress: sideWBTC,
            syntheticAddress: address(0)
        }));
        
        // Deploy all synthetic tokens
        for (uint256 i = 0; i < syntheticTokens.length; i++) {
            TokenInfo storage token = syntheticTokens[i];
            
            try syntheticFactory.createSyntheticToken(
                sideChainId,                // sourceChainId
                token.tokenAddress,         // sourceToken
                uint32(block.chainid),     // targetChainId (core chain)
                token.name,                // name
                token.symbol,              // symbol
                token.decimals,            // sourceDecimals
                token.decimals             // syntheticDecimals
            ) returns (address syntheticAddr) {
                token.syntheticAddress = syntheticAddr;
                deployments.push(Deployment(token.symbol, syntheticAddr));
                deployed[token.symbol] = DeployedContract(syntheticAddr, true);
            } catch {
                // Skip failed deployments silently
            }
        }
    }
    
    function _printDeployedTokens() internal view {
        for (uint256 i = 0; i < nativeTokens.length; i++) {
            console.log("%s=%s", nativeTokens[i].symbol, nativeTokens[i].tokenAddress);
        }
        for (uint256 i = 0; i < syntheticTokens.length; i++) {
            if (syntheticTokens[i].syntheticAddress != address(0)) {
                console.log("%s=%s", syntheticTokens[i].symbol, syntheticTokens[i].syntheticAddress);
            }
        }
    }
    
    function _fileExists(string memory filePath) internal view returns (bool) {
        try vm.fsMetadata(filePath) returns (Vm.FsMetadata memory) {
            return true;
        } catch {
            return false;
        }
    }
}