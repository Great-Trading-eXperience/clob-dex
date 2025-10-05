// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../src/core/TokenRegistry.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/ChainBalanceManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Configure BalanceManager
 * @dev Configures BalanceManager for cross-chain operations
 * Usage: SIDE_CHAIN=gtx-anvil-2 forge script script/ConfigureBalanceManager.s.sol:ConfigureBalanceManager --rpc-url https://core-devnet.gtxdex.xyz --broadcast
 */
contract ConfigureBalanceManager is DeployHelpers {
    
    // Core contracts
    TokenRegistry public tokenRegistry;
    BalanceManager public balanceManager;
    ChainBalanceManager public sideChainBM;
    
    // Side chain information
    uint32 public sideChainId;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== CONFIGURING BALANCE MANAGER ==========");
        
        // Load contracts from deployment
        _loadCoreContracts();
        
        // Load side chain configuration
        _loadSideChainConfig();
        
        console.log("TokenRegistry=%s", address(tokenRegistry));
        console.log("BalanceManager=%s", address(balanceManager));
        console.log("SideChainID=%s", sideChainId);
        console.log("SideChainBalanceManager=%s", address(sideChainBM));

        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Configure BalanceManager mailbox
        _configureBalanceManagerMailbox();
        
        // Step 2: Set TokenRegistry on BalanceManager (CRITICAL)
        _configureBalanceManagerTokenRegistry();
        
        // Step 3: Register ChainBalanceManager (CRITICAL)
        _registerChainBalanceManager();
        
        vm.stopBroadcast();
        
        console.log("\n========== CONFIGURATION SUMMARY ==========");
        console.log("# BalanceManager configuration completed successfully");
        console.log("TokenRegistry=%s", address(tokenRegistry));
        console.log("BalanceManager=%s", address(balanceManager));
        console.log("SideChainID=%s", sideChainId);
        console.log("# Cross-chain message handling enabled");
    }
    
    function _loadCoreContracts() internal {
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory deploymentPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        require(_fileExists(deploymentPath), "Core chain deployment file not found");
        
        string memory json = vm.readFile(deploymentPath);
        
        // Try different possible field names with env var support
        string memory tokenRegistryKey = vm.envOr("TOKEN_REGISTRY_KEY", string("PROXY_TOKENREGISTRY"));
        string memory balanceManagerKey = vm.envOr("BALANCE_MANAGER_KEY", string("PROXY_BALANCEMANAGER"));
        
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
        
        try vm.parseJsonAddress(json, string.concat(".", balanceManagerKey)) returns (address balanceManagerAddr) {
            balanceManager = BalanceManager(balanceManagerAddr);
        } catch {
            // Fallback to old naming
            try vm.parseJsonAddress(json, ".BalanceManager") returns (address balanceManagerAddr) {
                balanceManager = BalanceManager(balanceManagerAddr);
            } catch {
                revert("BalanceManager not found in deployment");
            }
        }
        
        require(address(tokenRegistry) != address(0), "TokenRegistry not found in deployment");
        require(address(balanceManager) != address(0), "BalanceManager not found in deployment");
    }
    
    function _loadSideChainConfig() internal {
        // Load side chain configuration from environment variables
        sideChainId = uint32(vm.envOr("SIDE_DOMAIN", uint256(31338)));
        
        // Load side chain ChainBalanceManager
        string memory root = vm.projectRoot();
        string memory sideChain = vm.envOr("SIDE_CHAIN", string("31338"));
        string memory sideDeployPath = string.concat(root, "/deployments/", sideChain, ".json");
        
        require(_fileExists(sideDeployPath), string.concat("Side chain deployment file not found: ", sideDeployPath));
        
        string memory sideJson = vm.readFile(sideDeployPath);
        address sideChainBMAddr = vm.parseJsonAddress(sideJson, ".ChainBalanceManager");
        
        require(sideChainBMAddr != address(0), "ChainBalanceManager not found in side chain deployment");
        
        sideChainBM = ChainBalanceManager(sideChainBMAddr);
        
        console.log("# Loaded side chain ChainBalanceManager from file=%s", sideDeployPath);
    }
    
    function _configureBalanceManagerMailbox() internal {
        console.log("========== CONFIGURING MAILBOX ==========");
        
        // Get mailbox configuration from environment
        address coreMailbox = vm.envOr("CORE_MAILBOX", 0x408F924BAEC71cC3968614Cb2c58E155A35e6890);
        uint32 coreDomain = uint32(vm.envOr("CORE_DOMAIN", uint256(31337)));
        
        console.log("CoreMailbox=%s", coreMailbox);
        console.log("CoreDomain=%s", coreDomain);
        
        // Check current configuration
        try balanceManager.getMailboxConfig() returns (address mailbox, uint32 localDomain) {
            if (mailbox != address(0)) {
                console.log("# BalanceManager mailbox already configured");
                console.log("CurrentMailbox=%s", mailbox);
                console.log("CurrentDomain=%s", localDomain);
                
                if (mailbox == coreMailbox && localDomain == coreDomain) {
                    console.log("# Mailbox configuration is correct");
                    return;
                } else {
                    console.log("# WARNING: Mailbox configuration mismatch - updating");
                }
            }
        } catch {
            console.log("# Mailbox not configured - setting now");
        }
        
        // Configure mailbox
        balanceManager.initializeCrossChain(coreMailbox, coreDomain);
        console.log("# BalanceManager mailbox configured successfully");
        
        // Verify configuration
        try balanceManager.getMailboxConfig() returns (address verifyMailbox, uint32 verifyDomain) {
            console.log("# Mailbox configuration verified");
            console.log("Mailbox=%s", verifyMailbox);
            console.log("Domain=%s", verifyDomain);
        } catch {
            console.log("# WARNING: Could not verify mailbox configuration");
        }
    }
    
    function _configureBalanceManagerTokenRegistry() internal {
        console.log("========== CONFIGURING TOKEN REGISTRY ==========");
        
        // Check current TokenRegistry configuration
        try balanceManager.getTokenRegistry() returns (address currentRegistry) {
            if (currentRegistry != address(0)) {
                console.log("# TokenRegistry already configured");
                console.log("Current=%s", currentRegistry);
                console.log("Expected=%s", address(tokenRegistry));
                
                if (currentRegistry == address(tokenRegistry)) {
                    console.log("# TokenRegistry configuration is correct");
                    return;
                } else {
                    console.log("# WARNING: TokenRegistry mismatch - updating");
                }
            }
        } catch {
            console.log("# TokenRegistry not configured - setting now");
        }
        
        // Set TokenRegistry
        console.log("Setting TokenRegistry=%s", address(tokenRegistry));
        
        balanceManager.setTokenRegistry(address(tokenRegistry));
        console.log("# BalanceManager TokenRegistry configured successfully");
        
        // Verify configuration immediately
        try balanceManager.getTokenRegistry() returns (address verifyRegistry) {
            if (verifyRegistry == address(tokenRegistry)) {
                console.log("# TokenRegistry verified=%s", verifyRegistry);
                console.log("# Cross-chain message handling now enabled");
            } else {
                console.log("# CRITICAL ERROR: TokenRegistry verification failed!");
                console.log("Expected=%s", address(tokenRegistry));
                console.log("Actual=%s", verifyRegistry);
                revert("DEPLOYMENT FAILED: TokenRegistry configuration not applied");
            }
        } catch {
            console.log("# CRITICAL ERROR: Cannot verify TokenRegistry configuration");
            revert("DEPLOYMENT FAILED: Cannot verify TokenRegistry");
        }
    }
    
    function _registerChainBalanceManager() internal {
        console.log("========== REGISTERING CHAIN BALANCE MANAGER ==========");
        
        console.log("SideChainID=%s", sideChainId);
        console.log("ChainBalanceManager=%s", address(sideChainBM));
        
        // Check current registration
        try balanceManager.getChainBalanceManager(sideChainId) returns (address currentCBM) {
            if (currentCBM != address(0)) {
                console.log("# ChainBalanceManager already registered");
                console.log("Current=%s", currentCBM);
                console.log("Expected=%s", address(sideChainBM));
                
                if (currentCBM == address(sideChainBM)) {
                    console.log("# ChainBalanceManager registration is correct");
                    return;
                } else {
                    console.log("# WARNING: ChainBalanceManager mismatch - updating");
                }
            }
        } catch {
            console.log("# ChainBalanceManager not registered - registering now");
        }
        
        // Register ChainBalanceManager
        balanceManager.setChainBalanceManager(sideChainId, address(sideChainBM));
        console.log("# ChainBalanceManager registered successfully");
        
        // Verify registration immediately
        try balanceManager.getChainBalanceManager(sideChainId) returns (address verifyCBM) {
            if (verifyCBM == address(sideChainBM)) {
                console.log("# ChainBalanceManager verified for chain=%s address=%s", sideChainId, verifyCBM);
                console.log("# Cross-chain message validation now enabled");
            } else {
                console.log("# CRITICAL ERROR: ChainBalanceManager verification failed!");
                console.log("ChainID=%s", sideChainId);
                console.log("Expected=%s", address(sideChainBM));
                console.log("Actual=%s", verifyCBM);
                revert("DEPLOYMENT FAILED: ChainBalanceManager registration not applied");
            }
        } catch {
            console.log("# CRITICAL ERROR: Cannot verify ChainBalanceManager registration");
            revert("DEPLOYMENT FAILED: Cannot verify ChainBalanceManager");
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