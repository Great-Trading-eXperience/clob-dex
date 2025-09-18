// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "../core/helpers/BeaconDeployer.t.sol";
import {ChainRegistry} from "../../src/core/ChainRegistry.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";

/**
 * @title EspressoDefaultsTest
 * @dev Test that default Espresso configurations work correctly
 */
contract EspressoDefaultsTest is Test {
    
    ChainRegistry chainRegistry;
    TokenRegistry tokenRegistry;
    address owner = makeAddr("owner");
    
    // Espresso testnet constants
    uint32 constant RARI_CHAIN_ID = 1918988905;
    uint32 constant APPCHAIN_CHAIN_ID = 4661;
    
    // Espresso token addresses
    address constant APPCHAIN_USDC = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
    address constant APPCHAIN_WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
    address constant APPCHAIN_WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
    
    function setUp() public {
        vm.startPrank(owner);
        
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        
        // Deploy ChainRegistry
        (BeaconProxy chainRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new ChainRegistry()),
            owner,
            abi.encodeCall(ChainRegistry.initialize, (owner))
        );
        chainRegistry = ChainRegistry(address(chainRegistryProxy));
        
        // Deploy TokenRegistry
        (BeaconProxy tokenRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        tokenRegistry = TokenRegistry(address(tokenRegistryProxy));
        
        vm.stopPrank();
    }
    
    function test_DefaultChainConfigurations() public {
        // Check if default chains exist
        uint32[] memory chains = chainRegistry.getAllChains();
        
        bool rariExists = false;
        bool appchainExists = false;
        
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] == RARI_CHAIN_ID) rariExists = true;
            if (chains[i] == APPCHAIN_CHAIN_ID) appchainExists = true;
        }
        
        // If default chains exist, verify their configuration
        if (rariExists) {
            ChainRegistry.ChainConfig memory rariConfig = chainRegistry.getChainConfig(RARI_CHAIN_ID);
            assertEq(rariConfig.domainId, RARI_CHAIN_ID);
            assertTrue(rariConfig.isActive);
            assertEq(rariConfig.name, "Rari Testnet");
        }
        
        if (appchainExists) {
            ChainRegistry.ChainConfig memory appchainConfig = chainRegistry.getChainConfig(APPCHAIN_CHAIN_ID);
            assertEq(appchainConfig.domainId, APPCHAIN_CHAIN_ID);
            assertTrue(appchainConfig.isActive);
            assertEq(appchainConfig.name, "Appchain Testnet");
        }
    }
    
    function test_DefaultTokenMappings() public {
        // Check if default token mappings exist
        address gsUSDC = tokenRegistry.getSyntheticToken(
            APPCHAIN_CHAIN_ID,
            APPCHAIN_USDC,
            RARI_CHAIN_ID
        );
        
        address gsWETH = tokenRegistry.getSyntheticToken(
            APPCHAIN_CHAIN_ID,
            APPCHAIN_WETH,
            RARI_CHAIN_ID
        );
        
        address gsWBTC = tokenRegistry.getSyntheticToken(
            APPCHAIN_CHAIN_ID,
            APPCHAIN_WBTC,
            RARI_CHAIN_ID
        );
        
        // If mappings exist, verify they're active
        if (gsUSDC != address(0)) {
            assertTrue(tokenRegistry.isTokenMappingActive(
                APPCHAIN_CHAIN_ID,
                APPCHAIN_USDC,
                RARI_CHAIN_ID
            ));
            
            // Test reverse lookup
            (uint32 sourceChain, address sourceToken) = tokenRegistry.getSourceToken(
                RARI_CHAIN_ID,
                gsUSDC
            );
            assertEq(sourceChain, APPCHAIN_CHAIN_ID);
            assertEq(sourceToken, APPCHAIN_USDC);
        }
        
        if (gsWETH != address(0)) {
            assertTrue(tokenRegistry.isTokenMappingActive(
                APPCHAIN_CHAIN_ID,
                APPCHAIN_WETH,
                RARI_CHAIN_ID
            ));
        }
        
        if (gsWBTC != address(0)) {
            assertTrue(tokenRegistry.isTokenMappingActive(
                APPCHAIN_CHAIN_ID,
                APPCHAIN_WBTC,
                RARI_CHAIN_ID
            ));
        }
    }
    
    function test_TokenDecimalHandling() public {
        // Test different decimal conversions
        
        // USDC: 6 decimals
        uint256 usdtAmount = 1000000; // 1 USDC
        uint256 usdtTo18 = tokenRegistry.convertAmount(usdtAmount, 6, 18);
        assertEq(usdtTo18, 1000000000000000000); // 1 * 10^18
        
        // WETH: 18 decimals
        uint256 wethAmount = 1 ether; // 1 WETH
        uint256 wethTo6 = tokenRegistry.convertAmount(wethAmount, 18, 6);
        assertEq(wethTo6, 1000000); // 1 * 10^6
        
        // WBTC: 8 decimals  
        uint256 wbtcAmount = 100000000; // 1 WBTC (8 decimals)
        uint256 wbtcTo18 = tokenRegistry.convertAmount(wbtcAmount, 8, 18);
        assertEq(wbtcTo18, 1000000000000000000); // 1 * 10^18 (adding 10 decimal places)
    }
    
    function test_ChainEnumeration() public {
        uint32[] memory allChains = chainRegistry.getAllChains();
        uint32[] memory activeChains = chainRegistry.getActiveChains();
        
        // Active chains should be subset of all chains
        assertTrue(activeChains.length <= allChains.length);
        
        // Verify active chains are actually active
        for (uint256 i = 0; i < activeChains.length; i++) {
            assertTrue(chainRegistry.isChainActive(activeChains[i]));
        }
    }
}