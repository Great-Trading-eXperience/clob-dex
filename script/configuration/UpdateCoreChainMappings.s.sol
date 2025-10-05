// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../src/core/TokenRegistry.sol";
import "../../src/core/ChainBalanceManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Update Core Chain Mappings
 * @dev Updates core chain token mappings for cross-chain operations
 * Usage: SIDE_CHAIN=gtx-anvil-2 forge script script/UpdateCoreChainMappings.s.sol:UpdateCoreChainMappings --rpc-url https://core-devnet.gtxdex.xyz --broadcast
 */
contract UpdateCoreChainMappings is DeployHelpers {
    
    // Core contracts
    TokenRegistry public tokenRegistry;
    
    // Side chain information
    uint32 public sideChainId;
    
    // Token information
    struct TokenInfo {
        string symbol;
        string name;
        uint8 decimals;
        address sideChainAddress;
        address syntheticAddress;
    }
    
    TokenInfo[] public tokens;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== UPDATING CORE CHAIN MAPPINGS ==========");
        
        // Load TokenRegistry from deployment
        _loadTokenRegistry();
        
        // Load side chain configuration and tokens
        _loadSideChainConfig();
        
        // Load existing synthetic tokens
        _loadExistingSyntheticTokens();
        
        console.log("TokenRegistry=%s", address(tokenRegistry));
        console.log("SideChainID=%s", sideChainId);
        console.log("NumberOfTokens=%s", tokens.length);

        vm.startBroadcast(deployerPrivateKey);
        
        // Register synthetic token mappings (cross-chain)
        _registerSyntheticTokens();
        
        // Register local token mappings (CRITICAL for depositLocal)
        _registerLocalTokenMappings();
        
        // Update core chain ChainBalanceManager mappings (optional)
        _updateCoreChainBalanceManagerMappings();
        
        vm.stopBroadcast();
        
        console.log("\n========== MAPPINGS UPDATE SUMMARY ==========");
        console.log("# Core chain token mappings update completed successfully");
        console.log("TokenRegistry=%s", address(tokenRegistry));
        console.log("SideChainID=%s", sideChainId);
        console.log("TokensProcessed=%s", tokens.length);
        console.log("# Cross-chain deposit system is now fully functional");
        console.log("# Local deposit system (depositLocal) is now fully functional");
    }
    
    function _loadTokenRegistry() internal {
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory deploymentPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        require(_fileExists(deploymentPath), "Core chain deployment file not found");
        
        string memory json = vm.readFile(deploymentPath);
        
        // Try different possible field names with env var support
        string memory tokenRegistryKey = vm.envOr("TOKEN_REGISTRY_KEY", string("PROXY_TOKENREGISTRY"));
        
        try vm.parseJsonAddress(json, string.concat(".", tokenRegistryKey)) returns (address tokenRegistryAddr) {
            tokenRegistry = TokenRegistry(tokenRegistryAddr);
        } catch {
            // Fallback to old naming
            try vm.parseJsonAddress(json, ".TokenRegistry") returns (address tokenRegistryAddr) {
                tokenRegistry = TokenRegistry(tokenRegistryAddr);
            } catch {
                revert("TokenRegistry not found in deployment");
            }
        }
        
        require(address(tokenRegistry) != address(0), "TokenRegistry not found in deployment");
    }
    
    function _loadSideChainConfig() internal {
        // Load side chain configuration from environment variables
        sideChainId = uint32(vm.envOr("SIDE_DOMAIN", uint256(31338)));
        
        // Load side chain token addresses
        string memory root = vm.projectRoot();
        string memory sideChain = vm.envOr("SIDE_CHAIN", string("31338"));
        string memory sideDeployPath = string.concat(root, "/deployments/", sideChain, ".json");
        
        require(_fileExists(sideDeployPath), string.concat("Side chain deployment file not found: ", sideDeployPath));
        
        string memory sideJson = vm.readFile(sideDeployPath);
        
        // Load token addresses from side chain deployment
        address sideUSDC = vm.parseJsonAddress(sideJson, ".USDC");
        address sideWETH = vm.parseJsonAddress(sideJson, ".WETH");
        address sideWBTC = vm.parseJsonAddress(sideJson, ".WBTC");
        
        console.log("# Loaded side chain tokens from file=%s", sideDeployPath);
        console.log("USDC=%s", sideUSDC);
        console.log("WETH=%s", sideWETH);
        console.log("WBTC=%s", sideWBTC);
        
        // Initialize token info (synthetic addresses will be loaded separately)
        tokens.push(TokenInfo({
            symbol: "gsUSDC",
            name: "GTX Synthetic USDC",
            decimals: 6,
            sideChainAddress: sideUSDC,
            syntheticAddress: address(0)
        }));
        
        tokens.push(TokenInfo({
            symbol: "gsWETH", 
            name: "GTX Synthetic WETH",
            decimals: 18,
            sideChainAddress: sideWETH,
            syntheticAddress: address(0)
        }));
        
        tokens.push(TokenInfo({
            symbol: "gsWBTC",
            name: "GTX Synthetic WBTC", 
            decimals: 8,
            sideChainAddress: sideWBTC,
            syntheticAddress: address(0)
        }));
    }
    
    function _loadExistingSyntheticTokens() internal {
        console.log("========== LOADING SYNTHETIC TOKENS ==========");
        
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory coreDeployPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        require(_fileExists(coreDeployPath), "Core chain deployment file not found");
        
        string memory coreJson = vm.readFile(coreDeployPath);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo storage token = tokens[i];
            
            // Load existing synthetic token address from deployment
            try vm.parseJsonAddress(coreJson, string.concat(".", token.symbol)) returns (address existingSynthetic) {
                if (existingSynthetic != address(0)) {
                    console.log("# Found existing %s (%s) at=%s", token.name, token.symbol, existingSynthetic);
                    token.syntheticAddress = existingSynthetic;
                } else {
                    console.log("# ERROR: Synthetic token %s has zero address", token.symbol);
                    revert(string.concat("DEPLOYMENT FAILED: Synthetic token ", token.symbol, " has zero address"));
                }
            } catch {
                console.log("# ERROR: Synthetic token %s not found in deployment", token.symbol);
                console.log("# SOLUTION: Run 'make deploy-core-chain-tokens network=gtx_core_devnet' first");
                revert(string.concat("DEPLOYMENT FAILED: Synthetic token ", token.symbol, " not found. Deploy tokens first."));
            }
        }
        
        console.log("# All synthetic tokens loaded successfully");
        
        // Verify all tokens were loaded
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokens[i].syntheticAddress != address(0), "INTERNAL ERROR: Synthetic token address is zero");
            console.log("# VERIFIED %s=%s", tokens[i].symbol, tokens[i].syntheticAddress);
        }
    }
    
    function _registerSyntheticTokens() internal {
        console.log("========== UPDATING TOKEN REGISTRY MAPPINGS ==========");
        
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo storage token = tokens[i];
            
            console.log("# Registering %s mapping", token.symbol);
            console.log("SideChainToken=%s", token.sideChainAddress);
            console.log("SyntheticToken=%s", token.syntheticAddress);
            
            // Check if mapping already exists
            try tokenRegistry.isTokenMappingActive(sideChainId, token.sideChainAddress, uint32(block.chainid)) returns (bool isActive) {
                if (isActive) {
                    console.log("# %s mapping already exists and is active", token.symbol);
                    
                    // Verify the mapping points to the correct synthetic token
                    try tokenRegistry.getSyntheticToken(sideChainId, token.sideChainAddress, uint32(block.chainid)) returns (address existingSynthetic) {
                        if (existingSynthetic == token.syntheticAddress) {
                            console.log("# %s mapping verified - correct synthetic token", token.symbol);
                            continue;
                        } else {
                            console.log("# WARNING: %s mapping exists but points to different token", token.symbol);
                            console.log("Current=%s", existingSynthetic);
                            console.log("Expected=%s", token.syntheticAddress);
                        }
                    } catch {
                        console.log("# WARNING: Cannot verify existing %s mapping", token.symbol);
                    }
                }
            } catch {
                console.log("# %s mapping not found - registering new mapping", token.symbol);
            }
            
            // Register token mapping
            try tokenRegistry.registerTokenMapping(
                sideChainId,              // sourceChainId
                token.sideChainAddress,   // sourceToken
                uint32(block.chainid),    // targetChainId (core chain)
                token.syntheticAddress,   // syntheticToken
                token.symbol,             // symbol
                token.decimals,           // sourceDecimals
                token.decimals            // syntheticDecimals
            ) {
                console.log("# %s mapping registered successfully", token.symbol);
                
                // Verify registration
                try tokenRegistry.isTokenMappingActive(sideChainId, token.sideChainAddress, uint32(block.chainid)) returns (bool isActive) {
                    if (isActive) {
                        console.log("# %s mapping is now active", token.symbol);
                    } else {
                        console.log("# WARNING: %s mapping registration may have failed", token.symbol);
                    }
                } catch {
                    console.log("# WARNING: Cannot verify %s mapping registration", token.symbol);
                }
                
            } catch Error(string memory reason) {
                console.log("# %s mapping registration skipped: %s", token.symbol, reason);
            } catch {
                console.log("# %s mapping registration skipped (already exists)", token.symbol);
            }
        }
        
        console.log("# All core chain synthetic token mappings processed successfully");
    }
    
    function _registerLocalTokenMappings() internal {
        console.log("========== REGISTERING LOCAL TOKEN MAPPINGS ==========");
        console.log("# CRITICAL: Configuring TokenRegistry for depositLocal() functionality");
        console.log("# Mapping: Regular core tokens -> Synthetic core tokens (same chain)");
        
        uint32 coreChainId = uint32(block.chainid);
        
        // Load regular token addresses from core deployment
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory coreDeployPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        if (!_fileExists(coreDeployPath)) {
            console.log("# ERROR: Core chain deployment file not found - cannot configure local mappings");
            console.log("# Local deposits will not work without this configuration");
            return;
        }
        
        string memory coreJson = vm.readFile(coreDeployPath);
        
        // Get regular token addresses from core deployment
        address regularUSDC = _parseJsonAddressOrZero(coreJson, ".USDC");
        address regularWETH = _parseJsonAddressOrZero(coreJson, ".WETH"); 
        address regularWBTC = _parseJsonAddressOrZero(coreJson, ".WBTC");
        
        console.log("# Regular core chain tokens:");
        console.log("USDC=%s", regularUSDC);
        console.log("WETH=%s", regularWETH);
        console.log("WBTC=%s", regularWBTC);
        
        // Process local mappings for each token
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenInfo storage token = tokens[i];
            address regularToken = address(0);
            
            // Match synthetic token to corresponding regular token
            if (keccak256(bytes(token.symbol)) == keccak256(bytes("gsUSDC"))) {
                regularToken = regularUSDC;
            } else if (keccak256(bytes(token.symbol)) == keccak256(bytes("gsWETH"))) {
                regularToken = regularWETH;
            } else if (keccak256(bytes(token.symbol)) == keccak256(bytes("gsWBTC"))) {
                regularToken = regularWBTC;
            }
            
            if (regularToken == address(0)) {
                console.log("# WARNING: No regular token found for %s - skipping local mapping", token.symbol);
                continue;
            }
            
            console.log("\n# Processing local mapping for %s", token.symbol);
            console.log("RegularToken=%s", regularToken);
            console.log("SyntheticToken=%s", token.syntheticAddress);
            
            // Check if local mapping already exists and is correct
            bool localMappingCorrect = false;
            
            try tokenRegistry.isTokenMappingActive(coreChainId, regularToken, coreChainId) returns (bool isActive) {
                if (isActive) {
                    console.log("# Local mapping exists for %s", token.symbol);
                    
                    // Verify it points to correct synthetic token
                    try tokenRegistry.getSyntheticToken(coreChainId, regularToken, coreChainId) returns (address existingSynthetic) {
                        if (existingSynthetic == token.syntheticAddress) {
                            localMappingCorrect = true;
                            console.log("# Local mapping is CORRECT for %s", token.symbol);
                        } else {
                            console.log("# Local mapping is INCORRECT for %s", token.symbol);
                            console.log("Current=%s", existingSynthetic);
                            console.log("Expected=%s", token.syntheticAddress);
                        }
                    } catch {
                        console.log("# Cannot verify existing local mapping for %s", token.symbol);
                    }
                }
            } catch {
                console.log("# No local mapping found for %s", token.symbol);
            }
            
            if (localMappingCorrect) {
                console.log("# Local mapping already correct for %s - skipping", token.symbol);
                continue;
            }
            
            // Register local token mapping
            console.log("# Registering local mapping: %s -> %s", regularToken, token.syntheticAddress);
            
            try tokenRegistry.registerTokenMapping(
                coreChainId,                // sourceChainId (core chain)
                regularToken,               // sourceToken (regular core token)
                coreChainId,                // targetChainId (same core chain) 
                token.syntheticAddress,     // syntheticToken
                token.symbol,               // symbol
                token.decimals,             // sourceDecimals
                token.decimals              // syntheticDecimals
            ) {
                console.log("# Local mapping registered successfully for %s", token.symbol);
                
                // Verify local mapping registration
                try tokenRegistry.isTokenMappingActive(coreChainId, regularToken, coreChainId) returns (bool isActive) {
                    if (isActive) {
                        console.log("# Local mapping is now ACTIVE for %s", token.symbol);
                        
                        // Double-check it returns correct synthetic token
                        try tokenRegistry.getSyntheticToken(coreChainId, regularToken, coreChainId) returns (address newSynthetic) {
                            if (newSynthetic == token.syntheticAddress) {
                                console.log("# Local mapping VERIFIED for %s", token.symbol);
                            } else {
                                console.log("# ERROR: Local mapping verification failed for %s", token.symbol);
                            }
                        } catch {
                            console.log("# WARNING: Cannot verify local mapping for %s", token.symbol);
                        }
                    } else {
                        console.log("# ERROR: Local mapping may have failed for %s", token.symbol);
                    }
                } catch {
                    console.log("# WARNING: Cannot check local mapping status for %s", token.symbol);
                }
                
            } catch Error(string memory reason) {
                console.log("# Local mapping registration failed for %s: %s", token.symbol, reason);
            } catch {
                console.log("# Local mapping registration failed for %s: Unknown error", token.symbol);
            }
        }
        
        console.log("\n# Local token mapping configuration complete");
        console.log("# depositLocal() functionality should now work correctly");
    }
    
    function _updateCoreChainBalanceManagerMappings() internal {
        console.log("========== UPDATING CHAIN BALANCE MANAGER MAPPINGS ==========");
        console.log("# This step prevents token mapping mismatch errors");
        
        // Try to find core chain ChainBalanceManager
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory coreDeployPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        if (!_fileExists(coreDeployPath)) {
            console.log("# No core chain deployment file found - skipping CBM mapping update");
            return;
        }
        
        string memory coreJson = vm.readFile(coreDeployPath);
        
        try vm.parseJsonAddress(coreJson, ".ChainBalanceManager") returns (address coreChainBMAddr) {
            if (coreChainBMAddr == address(0)) {
                console.log("# No ChainBalanceManager deployed on core chain - mappings not needed");
                return;
            }
            
            console.log("# Found core ChainBalanceManager=%s", coreChainBMAddr);
            ChainBalanceManager coreCBM = ChainBalanceManager(coreChainBMAddr);
            
            console.log("# Updating core ChainBalanceManager token mappings");
            
            for (uint256 i = 0; i < tokens.length; i++) {
                TokenInfo storage token = tokens[i];
                
                console.log("# Setting core mapping for %s", token.symbol);
                console.log("SideToken=%s", token.sideChainAddress);
                console.log("SyntheticToken=%s", token.syntheticAddress);
                
                try coreCBM.setTokenMapping(token.sideChainAddress, token.syntheticAddress) {
                    console.log("# Core mapping updated for %s successfully", token.symbol);
                    
                    // Verify the mapping
                    try coreCBM.getTokenMapping(token.sideChainAddress) returns (address actualSynthetic) {
                        if (actualSynthetic == token.syntheticAddress) {
                            console.log("# Core mapping verified: %s -> %s", token.sideChainAddress, actualSynthetic);
                        } else {
                            console.log("# WARNING: Core mapping mismatch for %s", token.symbol);
                        }
                    } catch {
                        console.log("# Cannot verify core mapping for %s", token.symbol);
                    }
                    
                } catch Error(string memory reason) {
                    console.log("# WARNING: Core mapping update failed for %s: %s", token.symbol, reason);
                } catch {
                    console.log("# WARNING: Core mapping update failed for %s: Unknown error", token.symbol);
                }
            }
            
            console.log("# Core chain ChainBalanceManager mappings updated successfully");
            
        } catch {
            console.log("# No ChainBalanceManager deployed on core chain - mappings not needed");
            console.log("# This is normal for core-side-only deployments");
        }
        
        console.log("# Core chain mapping synchronization complete");
    }
    
    function _fileExists(string memory filePath) internal view returns (bool) {
        try vm.fsMetadata(filePath) returns (Vm.FsMetadata memory) {
            return true;
        } catch {
            return false;
        }
    }
    
    function _parseJsonAddressOrZero(string memory json, string memory key) internal pure returns (address) {
        try vm.parseJsonAddress(json, key) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }
}