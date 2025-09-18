// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import "../../src/core/ChainBalanceManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Update Side Chain Mappings
 * @dev Updates ChainBalanceManager token mappings on side chain
 * Usage: SIDE_CHAIN=gtx-anvil-2 make update-side-chain-mappings network=gtx_anvil_2
 */
contract UpdateSideChainMappings is DeployHelpers {
    
    struct TokenMapping {
        address sideToken;
        address syntheticToken;
        string symbol;
    }
    
    ChainBalanceManager chainBalanceManager;
    TokenMapping[] public mappings;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Load deployment files
        _loadDeployments();
        
        console.log("========== UPDATING SIDE CHAIN MAPPINGS ==========");
        console.log("ChainID=%s", block.chainid);
        console.log("ChainBalanceManager=%s", address(chainBalanceManager));
        console.log("MappingsToUpdate=%s", mappings.length);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Update all token mappings
        for (uint256 i = 0; i < mappings.length; i++) {
            TokenMapping memory tokenMapping = mappings[i];
            
            console.log("# Updating %s mapping", tokenMapping.symbol);
            console.log("SideToken=%s", tokenMapping.sideToken);
            console.log("SyntheticToken=%s", tokenMapping.syntheticToken);
            
            try chainBalanceManager.setTokenMapping(tokenMapping.sideToken, tokenMapping.syntheticToken) {
                console.log("# %s mapping updated successfully", tokenMapping.symbol);
            } catch Error(string memory reason) {
                console.log("# ERROR: Failed to update %s: %s", tokenMapping.symbol, reason);
                revert(string.concat("Failed to update mapping for ", tokenMapping.symbol));
            }
        }
        
        vm.stopBroadcast();
        
        // Verify all mappings
        console.log("\n========== VERIFYING MAPPINGS ==========");
        for (uint256 i = 0; i < mappings.length; i++) {
            TokenMapping memory tokenMapping = mappings[i];
            
            try chainBalanceManager.getTokenMapping(tokenMapping.sideToken) returns (address actualSynthetic) {
                if (actualSynthetic == tokenMapping.syntheticToken) {
                    console.log("# %s verified: %s -> %s", tokenMapping.symbol, tokenMapping.sideToken, actualSynthetic);
                } else {
                    console.log("# ERROR: %s mismatch: expected %s, got %s", tokenMapping.symbol, tokenMapping.syntheticToken, actualSynthetic);
                    revert(string.concat("Verification failed for ", tokenMapping.symbol));
                }
            } catch {
                console.log("# ERROR: Failed to verify %s mapping", tokenMapping.symbol);
                revert(string.concat("Failed to verify mapping for ", tokenMapping.symbol));
            }
        }
        
        console.log("\n========== MAPPINGS UPDATE SUMMARY ==========");
        console.log("# All side chain mappings updated and verified successfully");
        console.log("ChainBalanceManager=%s", address(chainBalanceManager));
        console.log("MappingsUpdated=%s", mappings.length);
        console.log("# Cross-chain deposits are now ready to use");
    }
    
    function _loadDeployments() internal {
        string memory root = vm.projectRoot();
        
        // Load side chain deployment from environment variables
        string memory sideChain = vm.envOr("SIDE_CHAIN", string("31338"));
        string memory sideDeployPath = string.concat(root, "/deployments/", sideChain, ".json");
        require(fileExists(sideDeployPath), "Side chain deployment file not found");
        
        string memory sideJson = vm.readFile(sideDeployPath);
        
        // Load ChainBalanceManager
        address cbmAddr = vm.parseJsonAddress(sideJson, ".ChainBalanceManager");
        chainBalanceManager = ChainBalanceManager(cbmAddr);
        
        // Load side chain tokens
        address sideUSDC = vm.parseJsonAddress(sideJson, ".USDC");
        address sideWETH = vm.parseJsonAddress(sideJson, ".WETH");
        address sideWBTC = vm.parseJsonAddress(sideJson, ".WBTC");
        
        // Load core chain deployment to get synthetic tokens
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        string memory coreDeployPath = string.concat(root, "/deployments/", coreChain, ".json");
        require(fileExists(coreDeployPath), "Core chain deployment file not found");
        
        string memory coreJson = vm.readFile(coreDeployPath);
        address gsUSDC = vm.parseJsonAddress(coreJson, ".gsUSDC");
        address gsWETH = vm.parseJsonAddress(coreJson, ".gsWETH");
        address gsWBTC = vm.parseJsonAddress(coreJson, ".gsWBTC");
        
        console.log("# Loaded deployments");
        console.log("SideUSDC=%s -> CoregsUSDC=%s", sideUSDC, gsUSDC);
        console.log("SideWETH=%s -> CoregsWETH=%s", sideWETH, gsWETH);
        console.log("SideWBTC=%s -> CoregsWBTC=%s", sideWBTC, gsWBTC);
        
        // Create token mappings
        mappings.push(TokenMapping(sideUSDC, gsUSDC, "gsUSDC"));
        mappings.push(TokenMapping(sideWETH, gsWETH, "gsWETH"));
        mappings.push(TokenMapping(sideWBTC, gsWBTC, "gsWBTC"));
    }
}