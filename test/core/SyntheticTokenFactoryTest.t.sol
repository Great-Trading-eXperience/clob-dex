// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {BeaconDeployer} from "./helpers/BeaconDeployer.t.sol";
import {SyntheticTokenFactory} from "../../src/core/SyntheticTokenFactory.sol";
import {SyntheticTokenFactoryStorage} from "../../src/core/storages/SyntheticTokenFactoryStorage.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {SyntheticToken} from "../../src/token/SyntheticToken.sol";

contract SyntheticTokenFactoryTest is Test {
    SyntheticTokenFactory factory;
    TokenRegistry tokenRegistry;
    address owner = makeAddr("owner");
    address bridgeReceiver = makeAddr("bridgeReceiver");
    
    function setUp() public {
        vm.startPrank(owner);
        
        BeaconDeployer beaconDeployer = new BeaconDeployer();
        
        // Deploy TokenRegistry
        (BeaconProxy tokenRegistryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new TokenRegistry()),
            owner,
            abi.encodeCall(TokenRegistry.initialize, (owner))
        );
        tokenRegistry = TokenRegistry(address(tokenRegistryProxy));
        
        // Deploy SyntheticTokenFactory
        (BeaconProxy factoryProxy,) = beaconDeployer.deployUpgradeableContract(
            address(new SyntheticTokenFactory()),
            owner,
            abi.encodeCall(SyntheticTokenFactory.initialize, (owner, address(tokenRegistry), bridgeReceiver))
        );
        factory = SyntheticTokenFactory(address(factoryProxy));
        
        // Transfer TokenRegistry ownership to factory to allow it to register mappings
        tokenRegistry.transferOwnership(address(factory));
        
        vm.stopPrank();
    }
    
    function test_CreateSyntheticToken() public {
        vm.startPrank(owner);
        
        uint32 sourceChainId = 5000; // Test chain
        address sourceToken = makeAddr("testToken"); // Test token
        uint32 targetChainId = 6000; // Test target chain
        
        address syntheticToken = factory.createSyntheticToken(
            sourceChainId,
            sourceToken,
            targetChainId,
            "Synthetic USDC",
            "sUSDC",
            6,  // source decimals
            18  // synthetic decimals
        );
        
        // Verify synthetic token was created
        assertNotEq(syntheticToken, address(0));
        
        // Verify mappings
        address retrievedSynthetic = factory.getSyntheticToken(sourceChainId, sourceToken);
        assertEq(retrievedSynthetic, syntheticToken);
        
        // Verify source token info
        SyntheticTokenFactoryStorage.SourceTokenInfo memory info = factory.getSourceTokenInfo(syntheticToken);
        assertEq(info.sourceChainId, sourceChainId);
        assertEq(info.sourceToken, sourceToken);
        assertEq(info.sourceDecimals, 6);
        assertEq(info.syntheticDecimals, 18);
        assertTrue(info.isActive);
        
        // Verify token registry integration
        address registryToken = tokenRegistry.getSyntheticToken(sourceChainId, sourceToken, targetChainId);
        assertEq(registryToken, syntheticToken);
        
        vm.stopPrank();
    }
    
    function test_BatchCreateSyntheticTokens() public {
        vm.startPrank(owner);
        
        uint32 targetChainId = 6000; // Test target chain
        
        SyntheticTokenFactoryStorage.TokenCreationParams[] memory params = 
            new SyntheticTokenFactoryStorage.TokenCreationParams[](3);
        
        params[0] = SyntheticTokenFactoryStorage.TokenCreationParams({
            sourceChainId: 5000,
            sourceToken: makeAddr("token1"),
            name: "Synthetic Token1",
            symbol: "sT1",
            sourceDecimals: 6,
            syntheticDecimals: 18
        });
        
        params[1] = SyntheticTokenFactoryStorage.TokenCreationParams({
            sourceChainId: 5000,
            sourceToken: makeAddr("token2"),
            name: "Synthetic Token2",
            symbol: "sT2",
            sourceDecimals: 18,
            syntheticDecimals: 18
        });
        
        params[2] = SyntheticTokenFactoryStorage.TokenCreationParams({
            sourceChainId: 5000,
            sourceToken: makeAddr("token3"),
            name: "Synthetic Token3",
            symbol: "sT3",
            sourceDecimals: 8,
            syntheticDecimals: 18
        });
        
        address[] memory syntheticTokens = factory.batchCreateSyntheticTokens(params, targetChainId);
        
        assertEq(syntheticTokens.length, 3);
        
        // Verify all tokens were created
        for (uint256 i = 0; i < params.length; i++) {
            assertNotEq(syntheticTokens[i], address(0));
            
            address retrieved = factory.getSyntheticToken(params[i].sourceChainId, params[i].sourceToken);
            assertEq(retrieved, syntheticTokens[i]);
        }
        
        // Verify enumeration
        address[] memory allTokens = factory.getAllSyntheticTokens();
        assertEq(allTokens.length, 3);
        
        address[] memory chainTokens = factory.getChainSyntheticTokens(5000);
        assertEq(chainTokens.length, 3);
        
        vm.stopPrank();
    }
    
    function test_ConvertAmount() public {
        vm.startPrank(owner);
        
        uint32 sourceChainId = 5000;
        address sourceToken = makeAddr("convertToken");
        uint32 targetChainId = 6000;
        
        address syntheticToken = factory.createSyntheticToken(
            sourceChainId,
            sourceToken,
            targetChainId,
            "Synthetic USDC",
            "sUSDC",
            6,  // source decimals (USDC)
            18  // synthetic decimals (standard ERC20)
        );
        
        // Test source to synthetic conversion (6 -> 18 decimals)
        uint256 sourceAmount = 1000000; // 1 USDC (6 decimals)
        uint256 syntheticAmount = factory.convertAmount(syntheticToken, sourceAmount, true);
        assertEq(syntheticAmount, 1000000000000000000); // 1 * 10^18
        
        // Test synthetic to source conversion (18 -> 6 decimals)
        uint256 synthAmount = 1000000000000000000; // 1 synthetic token (18 decimals)
        uint256 sourceConverted = factory.convertAmount(syntheticToken, synthAmount, false);
        assertEq(sourceConverted, 1000000); // 1 * 10^6
        
        vm.stopPrank();
    }
    
    function test_TokenStatusManagement() public {
        vm.startPrank(owner);
        
        uint32 sourceChainId = 5000;
        address sourceToken = makeAddr("statusToken");
        uint32 targetChainId = 6000;
        
        address syntheticToken = factory.createSyntheticToken(
            sourceChainId,
            sourceToken,
            targetChainId,
            "Synthetic USDC",
            "sUSDC",
            6,
            18
        );
        
        // Verify initially active
        assertTrue(factory.isSyntheticTokenActive(syntheticToken));
        
        // Deactivate token
        factory.setSyntheticTokenStatus(syntheticToken, false);
        assertFalse(factory.isSyntheticTokenActive(syntheticToken));
        
        // Reactivate token
        factory.setSyntheticTokenStatus(syntheticToken, true);
        assertTrue(factory.isSyntheticTokenActive(syntheticToken));
        
        vm.stopPrank();
    }
    
    function test_GetActiveSyntheticTokens() public {
        vm.startPrank(owner);
        
        uint32 targetChainId = 6000;
        
        // Create multiple tokens
        address token1 = factory.createSyntheticToken(5000, makeAddr("activeToken1"), targetChainId, "Token1", "T1", 18, 18);
        address token2 = factory.createSyntheticToken(5000, makeAddr("activeToken2"), targetChainId, "Token2", "T2", 18, 18);
        address token3 = factory.createSyntheticToken(5000, makeAddr("activeToken3"), targetChainId, "Token3", "T3", 18, 18);
        
        // All should be active initially
        address[] memory activeTokens = factory.getActiveSyntheticTokens();
        assertEq(activeTokens.length, 3);
        
        // Deactivate one token
        factory.setSyntheticTokenStatus(token2, false);
        
        activeTokens = factory.getActiveSyntheticTokens();
        assertEq(activeTokens.length, 2);
        
        // Verify the correct tokens are active
        bool token1Found = false;
        bool token3Found = false;
        for (uint256 i = 0; i < activeTokens.length; i++) {
            if (activeTokens[i] == token1) token1Found = true;
            if (activeTokens[i] == token3) token3Found = true;
            assertNotEq(activeTokens[i], token2); // token2 should not be in active list
        }
        assertTrue(token1Found);
        assertTrue(token3Found);
        
        vm.stopPrank();
    }
    
    function test_UpdateConfiguration() public {
        vm.startPrank(owner);
        
        address newTokenRegistry = makeAddr("newTokenRegistry");
        address newBridgeReceiver = makeAddr("newBridgeReceiver");
        
        // Update TokenRegistry
        factory.setTokenRegistry(newTokenRegistry);
        assertEq(factory.getTokenRegistry(), newTokenRegistry);
        
        // Update bridge receiver
        factory.setBridgeReceiver(newBridgeReceiver);
        assertEq(factory.getBridgeReceiver(), newBridgeReceiver);
        
        vm.stopPrank();
    }
    
    function test_RevertDuplicateToken() public {
        vm.startPrank(owner);
        
        uint32 sourceChainId = 5000;
        address sourceToken = makeAddr("duplicateToken");
        uint32 targetChainId = 6000;
        
        // Create first token
        factory.createSyntheticToken(
            sourceChainId,
            sourceToken,
            targetChainId,
            "Synthetic USDC",
            "sUSDC",
            6,
            18
        );
        
        // Try to create duplicate - should revert
        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyExists(uint32,address)", sourceChainId, sourceToken));
        factory.createSyntheticToken(
            sourceChainId,
            sourceToken,
            targetChainId,
            "Another USDC",
            "aUSDC",
            6,
            18
        );
        
        vm.stopPrank();
    }
}