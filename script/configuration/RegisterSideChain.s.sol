// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../src/core/ChainRegistry.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Register Side Chain
 * @dev Registers side chain in ChainRegistry for cross-chain operations
 * Usage: SIDE_CHAIN=gtx-anvil-2 forge script script/RegisterSideChain.s.sol:RegisterSideChain --rpc-url https://anvil.gtxdex.xyz --broadcast
 */
contract RegisterSideChain is DeployHelpers {
    
    // Chain Registry contract
    ChainRegistry public chainRegistry;
    
    // Side chain information
    string public sideChainName;
    uint32 public sideChainId;
    address public sideMailbox;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        console.log("========== REGISTERING SIDE CHAIN ==========");
        
        // Load ChainRegistry from deployment
        _loadChainRegistry();
        
        // Load side chain configuration
        _loadSideChainConfig();
        
        console.log("ChainRegistry=%s", address(chainRegistry));
        console.log("Side Chain=%s", sideChainName);
        console.log("Side Chain ID=%s", sideChainId);
        console.log("Side Mailbox=%s", sideMailbox);

        vm.startBroadcast(deployerPrivateKey);
        
        _registerSideChain();
        
        vm.stopBroadcast();
        
        console.log("\n========== REGISTRATION SUMMARY ==========");
        console.log("# Side chain registration completed successfully");
        console.log("Chain=%s", sideChainName);
        console.log("ChainID=%s", sideChainId);
        console.log("Mailbox=%s", sideMailbox);
    }
    
    function _loadChainRegistry() internal {
        string memory root = vm.projectRoot();
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory deploymentPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        require(_fileExists(deploymentPath), "Core chain deployment file not found");
        
        string memory json = vm.readFile(deploymentPath);
        
        // Try different possible field names with env var support
        string memory chainRegistryKey = vm.envOr("CHAIN_REGISTRY_KEY", string("PROXY_CHAINREGISTRY"));
        
        try vm.parseJsonAddress(json, string.concat(".", chainRegistryKey)) returns (address chainRegistryAddr) {
            chainRegistry = ChainRegistry(chainRegistryAddr);
        } catch {
            // Fallback to old naming
            try vm.parseJsonAddress(json, ".ChainRegistry") returns (address chainRegistryAddr) {
                chainRegistry = ChainRegistry(chainRegistryAddr);
            } catch {
                revert("ChainRegistry not found in deployment");
            }
        }
        
        require(address(chainRegistry) != address(0), "ChainRegistry not found in deployment");
    }
    
    function _loadSideChainConfig() internal {
        // Load side chain configuration from environment variables
        sideChainId = uint32(vm.envOr("SIDE_DOMAIN", uint256(31338)));
        sideMailbox = vm.envOr("SIDE_MAILBOX", 0xB06c856C8eaBd1d8321b687E188204C1018BC4E5);
        
        try vm.envString("SIDE_NAME") returns (string memory name) {
            sideChainName = name;
        } catch {
            sideChainName = "GTX Side Chain";
        }
    }
    
    function _registerSideChain() internal {
        console.log("========== REGISTERING SIDE CHAIN ==========");
        
        // Check if chain is already registered
        try chainRegistry.getChainConfig(sideChainId) returns (ChainRegistry.ChainConfig memory config) {
            if (config.domainId != 0) {
                console.log("# Side chain already registered");
                console.log("ChainID=%s", sideChainId);
                console.log("DomainID=%s", config.domainId);
                console.log("Mailbox=%s", config.mailbox);
                console.log("Name=%s", config.name);
                return;
            }
        } catch {
            console.log("# Side chain not registered - proceeding with registration");
        }
        
        // Register side chain
        console.log("# Registering side chain");
        console.log("ChainID=%s", sideChainId);
        console.log("DomainID=%s", sideChainId);
        console.log("Mailbox=%s", sideMailbox);
        console.log("Name=%s", sideChainName);
        
        chainRegistry.registerChain(
            sideChainId,        // chainId
            sideChainId,        // domainId (using same as chainId for simplicity)
            sideMailbox,        // mailbox
            "",                // rpcEndpoint (not needed for core functionality)
            sideChainName,     // name
            2000               // blockTime (2 seconds)
        );
        
        console.log("# Side chain registered successfully");
        
        // Verify registration
        try chainRegistry.getChainConfig(sideChainId) returns (ChainRegistry.ChainConfig memory config) {
            console.log("# Registration verified");
            console.log("ChainID=%s", sideChainId);
            console.log("DomainID=%s", config.domainId);
            console.log("Mailbox=%s", config.mailbox);
            console.log("Name=%s", config.name);
        } catch {
            console.log("# WARNING: Could not verify registration");
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