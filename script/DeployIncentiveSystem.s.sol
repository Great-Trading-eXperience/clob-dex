// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/token/GTXToken.sol";
import "../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import "../src/incentives/voting-controller/VotingControllerUpg.sol";
import "../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import "../src/incentives/libraries/WeekMath.sol";
import "../src/marketmaker/GTXMarketMakerFactory.sol";
import "../src/marketmaker/GTXMarketMakerVault.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./DeployHelpers.s.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract DeployIncentiveSystem is DeployHelpers {
    // Contract address keys
    string constant BALANCE_MANAGER_ADDRESS = "PROXY_BALANCEMANAGER";
    string constant POOL_MANAGER_ADDRESS = "PROXY_POOLMANAGER";
    string constant GTX_ROUTER_ADDRESS = "PROXY_ROUTER";
    
    // Incentive system address keys
    string constant GTX_TOKEN_ADDRESS = "GTX_TOKEN";
    string constant VOTING_ESCROW_ADDRESS = "VOTING_ESCROW";
    string constant VOTING_CONTROLLER_ADDRESS = "VOTING_CONTROLLER";
    string constant GAUGE_CONTROLLER_ADDRESS = "GAUGE_CONTROLLER";
    string constant MARKET_MAKER_FACTORY_ADDRESS = "MARKET_MAKER_FACTORY";
    string constant MARKET_MAKER_VAULT_IMPL_ADDRESS = "MARKET_MAKER_VAULT_IMPL";
    
    // Core contracts from existing deployment
    address balanceManagerProxy;
    address poolManagerProxy;
    address routerProxy;
    
    // Incentive system contracts
    GTXToken token;
    VotingEscrowMainchain veToken;
    VotingControllerUpg votingController;
    GTXMarketMakerVault vaultImplementation;
    GTXMarketMakerFactory factory;
    GaugeControllerMainchainUpg gaugeController;
    
    function run() public {
        loadDeployments();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        
        loadCoreContracts();
        
        bool hasToken = deployed[GTX_TOKEN_ADDRESS].isSet;
        bool hasVeToken = deployed[VOTING_ESCROW_ADDRESS].isSet;
        bool hasVotingController = deployed[VOTING_CONTROLLER_ADDRESS].isSet;
        bool hasVaultImpl = deployed[MARKET_MAKER_VAULT_IMPL_ADDRESS].isSet;
        bool hasFactory = deployed[MARKET_MAKER_FACTORY_ADDRESS].isSet;
        bool hasGaugeController = deployed[GAUGE_CONTROLLER_ADDRESS].isSet;

        vm.startBroadcast(deployerPrivateKey);

        if (!hasToken) {
            console.log("\n========== DEPLOYING GTX TOKEN ==========");
            token = new GTXToken();
            
            deployments.push(Deployment(GTX_TOKEN_ADDRESS, address(token)));
            deployed[GTX_TOKEN_ADDRESS] = DeployedContract(address(token), true);
            
            console.log("GTX_TOKEN=%s", address(token));
        } else {
            console.log("\n========== LOADING GTX TOKEN ==========");
            token = GTXToken(deployed[GTX_TOKEN_ADDRESS].addr);
            console.log("GTX_TOKEN=%s", address(token));
        }

        if (!hasVeToken) {
            console.log("\n========== DEPLOYING VOTING ESCROW ==========");
            veToken = new VotingEscrowMainchain(
                address(token),
                address(0),
                0
            );
            
            deployments.push(Deployment(VOTING_ESCROW_ADDRESS, address(veToken)));
            deployed[VOTING_ESCROW_ADDRESS] = DeployedContract(address(veToken), true);
            
            console.log("VOTING_ESCROW=%s", address(veToken));
        } else {
            console.log("\n========== LOADING VOTING ESCROW ==========");
            veToken = VotingEscrowMainchain(deployed[VOTING_ESCROW_ADDRESS].addr);
            console.log("VOTING_ESCROW=%s", address(veToken));
        }

        if (!hasVotingController) {
            console.log("\n========== DEPLOYING VOTING CONTROLLER ==========");
            VotingControllerUpg votingControllerImpl = new VotingControllerUpg(
                address(veToken),
                address(0)
            );
            
            TransparentUpgradeableProxy votingControllerProxy = new TransparentUpgradeableProxy(
                address(votingControllerImpl),
                owner,
                abi.encodeWithSelector(VotingControllerUpg.initialize.selector, 0)
            );
            
            votingController = VotingControllerUpg(address(votingControllerProxy));
            
            deployments.push(Deployment(VOTING_CONTROLLER_ADDRESS, address(votingController)));
            deployed[VOTING_CONTROLLER_ADDRESS] = DeployedContract(address(votingController), true);
            
            console.log("VOTING_CONTROLLER=%s", address(votingController));
        } else {
            console.log("\n========== LOADING VOTING CONTROLLER ==========");
            votingController = VotingControllerUpg(deployed[VOTING_CONTROLLER_ADDRESS].addr);
            console.log("VOTING_CONTROLLER=%s", address(votingController));
        }

        if (!hasVaultImpl) {
            console.log("\n========== DEPLOYING MARKET MAKER VAULT IMPLEMENTATION ==========");
            vaultImplementation = new GTXMarketMakerVault();
            
            deployments.push(Deployment(MARKET_MAKER_VAULT_IMPL_ADDRESS, address(vaultImplementation)));
            deployed[MARKET_MAKER_VAULT_IMPL_ADDRESS] = DeployedContract(address(vaultImplementation), true);
            
            console.log("MARKET_MAKER_VAULT_IMPL=%s", address(vaultImplementation));
        } else {
            console.log("\n========== LOADING MARKET MAKER VAULT IMPLEMENTATION ==========");
            vaultImplementation = GTXMarketMakerVault(deployed[MARKET_MAKER_VAULT_IMPL_ADDRESS].addr);
            console.log("MARKET_MAKER_VAULT_IMPL=%s", address(vaultImplementation));
        }

        if (!hasFactory) {
            console.log("\n========== LOADING MARKET MAKER FACTORY ===========\n");
            console.log("Will force deploy a new factory in the configuration step");
        } else {
            console.log("\n========== LOADING MARKET MAKER FACTORY ===========");
            factory = GTXMarketMakerFactory(deployed[MARKET_MAKER_FACTORY_ADDRESS].addr);
            console.log("MARKET_MAKER_FACTORY=%s", address(factory));
        }

        if (!hasGaugeController) {
            console.log("\n========== DEPLOYING GAUGE CONTROLLER ==========");
            GaugeControllerMainchainUpg gaugeControllerImpl = new GaugeControllerMainchainUpg(
                address(votingController),
                address(token),
                address(factory)
            );
            
            TransparentUpgradeableProxy gaugeControllerProxy = new TransparentUpgradeableProxy(
                address(gaugeControllerImpl),
                owner,
                abi.encodeWithSelector(GaugeControllerMainchainUpg.initialize.selector)
            );
            
            gaugeController = GaugeControllerMainchainUpg(address(gaugeControllerProxy));
            
            deployments.push(Deployment(GAUGE_CONTROLLER_ADDRESS, address(gaugeController)));
            deployed[GAUGE_CONTROLLER_ADDRESS] = DeployedContract(address(gaugeController), true);
            
            console.log("GAUGE_CONTROLLER=%s", address(gaugeController));
        } else {
            console.log("\n========== LOADING GAUGE CONTROLLER ==========");
            gaugeController = GaugeControllerMainchainUpg(deployed[GAUGE_CONTROLLER_ADDRESS].addr);
            console.log("GAUGE_CONTROLLER=%s", address(gaugeController));
        }

        console.log("\n========== CONFIGURING INCENTIVE SYSTEM ==========");
        
        console.log("\n========== FORCE DEPLOYING NEW MARKET MAKER FACTORY ==========\n");
        console.log("Deploying with owner address: %s", owner);
        
        if (deployed[MARKET_MAKER_FACTORY_ADDRESS].isSet) {
            console.log("Removing existing factory from deployments: %s", deployed[MARKET_MAKER_FACTORY_ADDRESS].addr);
            deployed[MARKET_MAKER_FACTORY_ADDRESS].isSet = false;
        }
        
        GTXMarketMakerFactory newFactoryImpl = new GTXMarketMakerFactory();
        console.log("Deployed factory implementation at: %s", address(newFactoryImpl));
        
        bytes memory factoryInitData = abi.encodeWithSelector(
            GTXMarketMakerFactory.initialize.selector,
            owner,
            address(veToken),
            address(gaugeController), 
            routerProxy,
            poolManagerProxy,
            balanceManagerProxy,
            address(vaultImplementation)
        );
        
        TransparentUpgradeableProxy newFactoryProxy = new TransparentUpgradeableProxy(
            address(newFactoryImpl),
            owner,
            factoryInitData
        );
        
        factory = GTXMarketMakerFactory(address(newFactoryProxy));
        console.log("Deployed factory proxy at: %s", address(factory));
        
        deployments.push(Deployment(MARKET_MAKER_FACTORY_ADDRESS, address(factory)));
        deployed[MARKET_MAKER_FACTORY_ADDRESS] = DeployedContract(address(factory), true);
        
        try OwnableUpgradeable(address(factory)).owner() returns (address factoryOwner) {
            console.log("Verified factory owner: %s", factoryOwner);
            if (factoryOwner != owner) {
                console.log("WARNING: Factory owner doesn't match expected owner!");
            }
            
            try factory.updateParameterConstraints(
                1000,   
                9000,   
                5,      
                500,    
                0.01 * 10**18, 
                100 * 10**18,
                10,     
                200,    
                2,      
                100,    
                5 minutes, 
                7 days    
            ) {
                console.log("Updated parameter constraints in Market Maker Factory");
            } catch (bytes memory reason) {
                console.log("Failed to update parameter constraints");
                console.logBytes(reason);
            }
        } catch {
            console.log("Failed to verify factory owner, but continuing with deployment");
        }

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Incentive System addresses saved to JSON file:");
        console.log("GTX_TOKEN=%s", address(token));
        console.log("VOTING_ESCROW=%s", address(veToken));
        console.log("VOTING_CONTROLLER=%s", address(votingController));
        console.log("GAUGE_CONTROLLER=%s", address(gaugeController));
        console.log("MARKET_MAKER_FACTORY=%s", address(factory));
        console.log("MARKET_MAKER_VAULT_IMPL=%s", address(vaultImplementation));
        
        vm.stopBroadcast();

        exportDeployments();
    }
    
    function loadCoreContracts() private {
        console.log("\n========== LOADING CORE CONTRACTS ==========");
        
        balanceManagerProxy = deployed[BALANCE_MANAGER_ADDRESS].addr;
        poolManagerProxy = deployed[POOL_MANAGER_ADDRESS].addr;
        routerProxy = deployed[GTX_ROUTER_ADDRESS].addr;
        
        require(balanceManagerProxy != address(0), "BalanceManager address not found in deployments");
        require(poolManagerProxy != address(0), "PoolManager address not found in deployments");
        require(routerProxy != address(0), "GTXRouter address not found in deployments");
        
        console.log("PROXY_BALANCEMANAGER=%s", balanceManagerProxy);
        console.log("PROXY_POOLMANAGER=%s", poolManagerProxy);
        console.log("PROXY_ROUTER=%s", routerProxy);
    }
}
