// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {ChainBalanceManager} from "../src/core/ChainBalanceManager.sol";

/**
 * @title SetupChainBalanceManager
 * @dev Complete setup for ChainBalanceManager with destination, whitelist, and token mapping
 */
contract SetupChainBalanceManager is Script {
    
    // Addresses
    address constant RARI_BALANCE_MANAGER = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    uint32 constant RARI_DOMAIN_ID = 1918988905;
    
    address constant APPCHAIN_CBM = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address constant APPCHAIN_USDC = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant RARI_GSUSDC = 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68;
    
    function run() public {
        console.log("=== Setting up ChainBalanceManager on Appchain ===");
        
        vm.startBroadcast();
        
        ChainBalanceManager cbm = ChainBalanceManager(APPCHAIN_CBM);
        
        // Step 1: Configure destination
        console.log("Step 1: Configuring destination...");
        try cbm.updateCrossChainConfig(RARI_DOMAIN_ID, RARI_BALANCE_MANAGER) {
            console.log("SUCCESS: Destination configured successfully");
        } catch {
            console.log("ERROR: Failed to configure destination - may need owner permissions");
        }
        
        // Step 2: Whitelist USDC
        console.log("Step 2: Whitelisting USDC...");
        try cbm.addToken(APPCHAIN_USDC) {
            console.log("SUCCESS: USDC whitelisted successfully");
        } catch {
            console.log("ERROR: Failed to whitelist USDC - may already be whitelisted or need permissions");
        }
        
        // Step 3: Set token mapping
        console.log("Step 3: Setting token mapping USDC -> gsUSDC...");
        try cbm.setTokenMapping(APPCHAIN_USDC, RARI_GSUSDC) {
            console.log("SUCCESS: Token mapping set successfully");
        } catch {
            console.log("ERROR: Failed to set token mapping - may need owner permissions");
        }
        
        vm.stopBroadcast();
        
        // Verify configuration
        console.log("=== Verification ===");
        
        try cbm.getCrossChainConfig() returns (uint32 domain, address bm) {
            console.log("Destination domain:", domain);
            console.log("Destination BalanceManager:", bm);
        } catch {
            console.log("Could not read cross-chain config");
        }
        
        try cbm.isTokenWhitelisted(APPCHAIN_USDC) returns (bool whitelisted) {
            console.log("USDC whitelisted:", whitelisted);
        } catch {
            console.log("Could not check USDC whitelist status");
        }
        
        try cbm.getTokenMapping(APPCHAIN_USDC) returns (address synthetic) {
            console.log("USDC -> Synthetic mapping:", synthetic);
            console.log("Expected gsUSDC:", RARI_GSUSDC);
            if (synthetic == RARI_GSUSDC) {
                console.log("SUCCESS: Token mapping correct!");
            } else {
                console.log("ERROR: Token mapping incorrect");
            }
        } catch {
            console.log("Could not read token mapping");
        }
        
        console.log("Setup completed!");
    }
}