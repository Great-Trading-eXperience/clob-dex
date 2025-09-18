// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Currency} from "../../src/core/libraries/Currency.sol";
import {PoolId} from "../../src/core/libraries/Pool.sol";
import {IOrderBook} from "../../src/core/interfaces/IOrderBook.sol";
import "../../src/core/PoolManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Create Trading Pools
 * @dev Creates all required trading pools for the GTX trading system
 * 
 * This script creates the following pools:
 * 1. Synthetic-to-Synthetic pairs: gsWETH/gsUSDC, gsWBTC/gsUSDC  
 * 2. Native-to-Native pairs: USDC/WETH, WETH/WBTC (optional)
 * 3. Native-to-Synthetic pairs: USDC/gsUSDC, WETH/gsWETH, WBTC/gsWBTC (optional)
 * 
 * Environment Variables:
 *   CORE_CHAIN           - Core chain deployment file (defaults to "31337")
 *   CREATE_NATIVE_POOLS  - Create native-to-native pools (defaults to "false")  
 *   CREATE_BRIDGE_POOLS  - Create native-to-synthetic pools (defaults to "false")
 * 
 * Usage: make create-trading-pools network=gtx_anvil
 */
contract CreateTradingPools is DeployHelpers {
    
    // Loaded contracts
    PoolManager poolManager;
    
    // Token addresses
    address gsUSDCAddress;
    address gsWETHAddress; 
    address gsWBTCAddress;
    address nativeUSDCAddress;
    address nativeWETHAddress;
    address nativeWBTCAddress;
    
    // Configuration
    bool createNativePools;
    bool createBridgePools;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== CREATING TRADING POOLS ==========");
        
        // Load configuration
        _loadConfiguration();
        
        // Load contracts and token addresses
        _loadContracts();
        
        console.log("PoolManager=%s", address(poolManager));
        console.log("gsUSDC=%s", gsUSDCAddress);
        console.log("gsWETH=%s", gsWETHAddress);
        console.log("gsWBTC=%s", gsWBTCAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Create all required pools
        _createAllPools();
        
        vm.stopBroadcast();
        
        console.log("\\n========== POOL CREATION SUMMARY ==========");
        console.log("# All required trading pools created successfully");
        console.log("PoolManager=%s", address(poolManager));
        console.log("# Trading system is now ready for use");
    }
    
    function _loadConfiguration() internal {
        // Load pool creation flags
        try vm.envBool("CREATE_NATIVE_POOLS") returns (bool flag) {
            createNativePools = flag;
        } catch {
            createNativePools = false;
        }
        
        try vm.envBool("CREATE_BRIDGE_POOLS") returns (bool flag) {
            createBridgePools = flag;
        } catch {
            createBridgePools = false;
        }
        
        console.log("CreateNativePools=%s", createNativePools);
        console.log("CreateBridgePools=%s", createBridgePools);
    }
    
    function _loadContracts() internal {
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory coreDeploymentPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        require(_fileExists(coreDeploymentPath), "Core chain deployment file not found");
        
        string memory coreJson = vm.readFile(coreDeploymentPath);
        
        // Load PoolManager
        try vm.parseJsonAddress(coreJson, ".PROXY_POOLMANAGER") returns (address poolManagerAddr) {
            poolManager = PoolManager(poolManagerAddr);
        } catch {
            try vm.parseJsonAddress(coreJson, ".PoolManager") returns (address poolManagerAddr) {
                poolManager = PoolManager(poolManagerAddr);
            } catch {
                revert("PoolManager not found in core chain deployment");
            }
        }
        
        // Load synthetic tokens (required)
        gsUSDCAddress = vm.parseJsonAddress(coreJson, ".gsUSDC");
        gsWETHAddress = vm.parseJsonAddress(coreJson, ".gsWETH");
        gsWBTCAddress = vm.parseJsonAddress(coreJson, ".gsWBTC");
        
        require(gsUSDCAddress != address(0), "gsUSDC not found in deployment");
        require(gsWETHAddress != address(0), "gsWETH not found in deployment");
        require(gsWBTCAddress != address(0), "gsWBTC not found in deployment");
        
        // Load native tokens (optional, only if creating native/bridge pools)
        if (createNativePools || createBridgePools) {
            try vm.parseJsonAddress(coreJson, ".USDC") returns (address addr) {
                nativeUSDCAddress = addr;
            } catch {
                console.log("# Native USDC not found, skipping native pools");
            }
            
            try vm.parseJsonAddress(coreJson, ".WETH") returns (address addr) {
                nativeWETHAddress = addr;
            } catch {
                console.log("# Native WETH not found, skipping native pools");
            }
            
            try vm.parseJsonAddress(coreJson, ".WBTC") returns (address addr) {
                nativeWBTCAddress = addr;
            } catch {
                console.log("# Native WBTC not found, skipping native pools");
            }
        }
    }
    
    function _createAllPools() internal {
        // Default trading rules for all pools
        IOrderBook.TradingRules memory defaultRules = IOrderBook.TradingRules({
            minTradeAmount: 1e6,    // 1 USDC equivalent minimum trade
            minAmountMovement: 1e4, // 0.01 units minimum movement
            minPriceMovement: 1e4,  // 0.01 price units minimum movement
            minOrderSize: 1e6       // 1 USDC equivalent minimum order size
        });
        
        console.log("========== CREATING SYNTHETIC TRADING POOLS ==========");
        
        // 1. Create synthetic-to-synthetic pools (REQUIRED for trading)
        _createPool(gsWETHAddress, gsUSDCAddress, "gsWETH/gsUSDC", defaultRules);
        _createPool(gsWBTCAddress, gsUSDCAddress, "gsWBTC/gsUSDC", defaultRules);
        
        // 2. Create native-to-native pools (OPTIONAL)
        if (createNativePools && nativeUSDCAddress != address(0) && nativeWETHAddress != address(0) && nativeWBTCAddress != address(0)) {
            console.log("========== CREATING NATIVE TRADING POOLS ==========");
            _createPool(nativeUSDCAddress, nativeWETHAddress, "USDC/WETH", defaultRules);
            _createPool(nativeWETHAddress, nativeWBTCAddress, "WETH/WBTC", defaultRules);
        }
        
        // 3. Create native-to-synthetic bridge pools (OPTIONAL)
        if (createBridgePools && nativeUSDCAddress != address(0) && nativeWETHAddress != address(0) && nativeWBTCAddress != address(0)) {
            console.log("========== CREATING BRIDGE POOLS ==========");
            _createPool(nativeUSDCAddress, gsUSDCAddress, "USDC/gsUSDC", defaultRules);
            _createPool(nativeWETHAddress, gsWETHAddress, "WETH/gsWETH", defaultRules);
            _createPool(nativeWBTCAddress, gsWBTCAddress, "WBTC/gsWBTC", defaultRules);
        }
    }
    
    function _createPool(address token1, address token2, string memory poolName, IOrderBook.TradingRules memory rules) internal {
        console.log("# Creating %s pool", poolName);
        console.log("Token1=%s", token1);
        console.log("Token2=%s", token2);
        
        Currency currency1 = Currency.wrap(token1);
        Currency currency2 = Currency.wrap(token2);
        
        // Check if pool already exists
        try poolManager.poolExists(currency1, currency2) returns (bool exists) {
            if (exists) {
                console.log("# Pool %s already exists", poolName);
                return;
            }
        } catch {
            // Continue with creation if check fails
        }
        
        // Create the pool
        try poolManager.createPool(currency1, currency2, rules) returns (PoolId poolId) {
            console.log("# Pool %s created successfully", poolName);
            
            // Try to get liquidity score
            try poolManager.getPoolLiquidityScore(currency1, currency2) returns (uint256 liquidityScore) {
                console.log("# Pool %s liquidity_score=%s", poolName, liquidityScore);
            } catch {
                console.log("# Pool %s liquidity_score=unknown", poolName);
            }
            
        } catch Error(string memory reason) {
            console.log("# ERROR: Failed to create %s pool: %s", poolName, reason);
            revert(string.concat("Failed to create pool: ", poolName));
        } catch {
            console.log("# ERROR: Failed to create %s pool: Unknown error", poolName);
            revert(string.concat("Failed to create pool: ", poolName));
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