// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../src/token/GTXToken.sol";
import "../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import "../src/incentives/voting-controller/VotingControllerUpg.sol";
import "../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import "../src/incentives/libraries/WeekMath.sol";
import "../src/marketmaker/GTXMarketMakerFactory.sol";
import "../src/marketmaker/GTXMarketMakerVault.sol";
import "./DeployHelpers.s.sol";
import "forge-std/console.sol";

contract SimulateVoting is DeployHelpers {
    // Contract address keys
    string constant GTX_TOKEN_ADDRESS = "GTX_TOKEN";
    string constant VOTING_ESCROW_ADDRESS = "VOTING_ESCROW";
    string constant VOTING_CONTROLLER_ADDRESS = "VOTING_CONTROLLER";
    string constant GAUGE_CONTROLLER_ADDRESS = "GAUGE_CONTROLLER";
    string constant MARKET_MAKER_FACTORY_ADDRESS = "MARKET_MAKER_FACTORY";
    
    // Incentive system contracts
    GTXToken token;
    VotingEscrowMainchain veToken;
    VotingControllerUpg votingController;
    GaugeControllerMainchainUpg gaugeController;
    GTXMarketMakerFactory factory;
    
    // Constants
    uint256 constant WEEK = 7 days;
    uint256 constant YEAR = 365 days;
    uint256 constant TOKEN_AMOUNT = 100_000 * 1e18; 
    uint256 constant LOCK_AMOUNT = 10_000 * 1e18;   
    uint256 constant TOKEN_PER_SEC = 1e16;          
    
    // Voting accounts
    address[] voters;
    string[] voterNames;
    
    // Pool addresses
    address[] pools;
    string[] poolNames;
    
    function run() public {
        loadDeployments();
        
        uint256 deployerPrivateKey = getDeployerKey();
        address owner = vm.addr(deployerPrivateKey);
        
        loadIncentiveContracts();
        
        configureVotersAndPools();
        
        vm.startBroadcast(deployerPrivateKey);
        
        if (token.balanceOf(owner) < TOKEN_AMOUNT * voters.length) {
            try token.mint(owner, TOKEN_AMOUNT * voters.length) {
                console.log("Minted %d tokens to owner for distribution", TOKEN_AMOUNT * voters.length / 1e18);
            } catch {
                console.log("Failed to mint tokens - owner might not have minter role");
            }
        }
        
        distributeTokens();
        
        lockTokens();
        
        voteForPools();
        
        fundGaugeController();
        
        finalizeEpoch();
        
        claimRewards();
        
        vm.stopBroadcast();
    }
    
    function loadIncentiveContracts() private {
        console.log("\n========== LOADING INCENTIVE SYSTEM CONTRACTS ==========");
        
        require(deployed[GTX_TOKEN_ADDRESS].isSet, "GTX Token not found in deployments");
        require(deployed[VOTING_ESCROW_ADDRESS].isSet, "Voting Escrow not found in deployments");
        require(deployed[VOTING_CONTROLLER_ADDRESS].isSet, "Voting Controller not found in deployments");
        require(deployed[GAUGE_CONTROLLER_ADDRESS].isSet, "Gauge Controller not found in deployments");
        require(deployed[MARKET_MAKER_FACTORY_ADDRESS].isSet, "Market Maker Factory not found in deployments");
        
        token = GTXToken(deployed[GTX_TOKEN_ADDRESS].addr);
        veToken = VotingEscrowMainchain(deployed[VOTING_ESCROW_ADDRESS].addr);
        votingController = VotingControllerUpg(deployed[VOTING_CONTROLLER_ADDRESS].addr);
        gaugeController = GaugeControllerMainchainUpg(deployed[GAUGE_CONTROLLER_ADDRESS].addr);
        factory = GTXMarketMakerFactory(deployed[MARKET_MAKER_FACTORY_ADDRESS].addr);
        
        console.log("GTX Token: %s", address(token));
        console.log("Voting Escrow: %s", address(veToken));
        console.log("Voting Controller: %s", address(votingController));
        console.log("Gauge Controller: %s", address(gaugeController));
        console.log("Market Maker Factory: %s", address(factory));
    }
    
    function configureVotersAndPools() private {
        console.log("\n========== CONFIGURING VOTERS AND POOLS ==========");
        
        addVoter("alice", vm.addr(uint256(keccak256("alice"))));
        addVoter("bob", vm.addr(uint256(keccak256("bob"))));
        addVoter("charlie", vm.addr(uint256(keccak256("charlie"))));
        
        for (uint256 i = 0; i < deployments.length; i++) {
            if (startsWith(deployments[i].name, "POOL_")) {
                pools.push(deployments[i].addr);
                poolNames.push(deployments[i].name);
                console.log("Found pool: %s at %s", deployments[i].name, deployments[i].addr);
            }
        }
        
        if (pools.length == 0) {
            console.log("No pools found in deployments, checking factory for vaults");
            
            try factory.getVaults() returns (address[] memory vaults) {
                for (uint256 i = 0; i < vaults.length; i++) {
                    pools.push(vaults[i]);
                    poolNames.push(string(abi.encodePacked("Vault_", vm.toString(i))));
                    console.log("Found vault: %s", vaults[i]);
                }
            } catch {
                console.log("Failed to get vaults from factory");
            }
        }
        
        if (pools.length == 0) {
            console.log("WARNING: No pools found. Please deploy pools first using DeployMarkets.s.sol");
        } else {
            console.log("Configured %d voters and %d pools", voters.length, pools.length);
        }
        
        try votingController.getPools() returns (address[] memory existingPools) {
            if (existingPools.length == 0 && pools.length > 0) {
                console.log("Adding pools to voting controller");
                uint64[] memory chainIds = new uint64[](pools.length);
                for (uint256 i = 0; i < pools.length; i++) {
                    chainIds[i] = uint64(block.chainid);
                }
                try votingController.addMultiPools(chainIds, pools) {
                    console.log("Successfully added pools to voting controller");
                } catch {
                    console.log("Failed to add pools to voting controller");
                }
            }
        } catch {
            console.log("Failed to get pools from voting controller");
        }
    }
    
    function distributeTokens() private {
        console.log("\n========== DISTRIBUTING TOKENS TO VOTERS ==========");
        
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            string memory name = voterNames[i];
            
            if (token.balanceOf(voter) < LOCK_AMOUNT) {
                try token.transfer(voter, TOKEN_AMOUNT) {
                    console.log("Transferred %d tokens to %s (%s)", TOKEN_AMOUNT / 1e18, name, voter);
                } catch {
                    console.log("Failed to transfer tokens to %s", name);
                }
            } else {
                console.log("%s already has sufficient tokens", name);
            }
        }
    }
    
    function lockTokens() private {
        console.log("\n========== LOCKING TOKENS FOR VOTING POWER ==========");
        
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            string memory name = voterNames[i];
            
            try veToken.balanceOf(voter) returns (uint256 balance) {
                if (balance > 0) {
                    console.log("%s already has %d voting power", name, balance / 1e18);
                    continue;
                }
            } catch {
                console.log("Failed to check voting power for %s", name);
            }
            
            vm.startPrank(voter);
            try token.approve(address(veToken), LOCK_AMOUNT) {
                console.log("%s approved tokens for locking", name);
            } catch {
                console.log("Failed to approve tokens for %s", name);
                vm.stopPrank();
                continue;
            }
            
            uint128 lockEnd = uint128(
                WeekMath.getWeekStartTimestamp(uint128(block.timestamp + YEAR)) + WEEK - 1
            );
            
            try veToken.createLock(LOCK_AMOUNT, lockEnd) {
                console.log("%s locked %d tokens until %s", name, LOCK_AMOUNT / 1e18, vm.toString(lockEnd));
            } catch {
                console.log("Failed to lock tokens for %s", name);
            }
            
            vm.stopPrank();
        }
    }
    
    function voteForPools() private {
        console.log("\n========== VOTING FOR POOLS ==========");
        
        if (pools.length == 0) {
            console.log("No pools to vote for");
            return;
        }
        
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            string memory name = voterNames[i];
            
            vm.startPrank(voter);
            
            uint64[] memory weights = new uint64[](pools.length);
            uint64 weight = uint64(1e18 / pools.length);
            
            for (uint256 j = 0; j < pools.length; j++) {
                weights[j] = weight;
            }
            
            try votingController.vote(pools, weights) {
                console.log("%s voted for %d pools with equal weight", name, pools.length);
            } catch {
                console.log("Failed to vote for %s", name);
            }
            
            vm.stopPrank();
        }
    }
    
    function fundGaugeController() private {
        console.log("\n========== FUNDING GAUGE CONTROLLER ==========");
        
        uint256 fundAmount = TOKEN_PER_SEC * WEEK;
        
        try token.approve(address(gaugeController), fundAmount) {
            console.log("Approved %d tokens for gauge controller", fundAmount / 1e18);
        } catch {
            console.log("Failed to approve tokens for gauge controller");
            return;
        }
        
        try gaugeController.fundToken(fundAmount) {
            console.log("Funded gauge controller with %d tokens", fundAmount / 1e18);
        } catch {
            console.log("Failed to fund gauge controller");
            return;
        }
        
        try votingController.setTokenPerSec(uint128(TOKEN_PER_SEC)) {
            console.log("Set token per second to %d", TOKEN_PER_SEC);
        } catch {
            console.log("Failed to set token per second");
        }
    }
    
    function finalizeEpoch() private {
        console.log("\n========== FINALIZING EPOCH ==========");
        
        console.log("Advancing time by 1 week");
        vm.warp(block.timestamp + WEEK);
        vm.roll(block.number + 50400); 
        
        try votingController.finalizeEpoch() {
            console.log("Finalized epoch");
        } catch {
            console.log("Failed to finalize epoch");
            return;
        }
        
        try votingController.broadcastResults(uint64(block.chainid)) {
            console.log("Broadcast results for chain %d", block.chainid);
        } catch {
            console.log("Failed to broadcast results");
        }
        
        console.log("Advancing time by 10 hours for rewards to accumulate");
        vm.warp(block.timestamp + 10 hours);
        vm.roll(block.number + 3000);
    }
    
    function claimRewards() private {
        console.log("\n========== CLAIMING REWARDS ==========");
        
        if (pools.length == 0) {
            console.log("No pools to claim rewards from");
            return;
        }
        
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            string memory name = voterNames[i];
            
            uint256 initialBalance = token.balanceOf(voter);
            
            vm.startPrank(voter);
            
            for (uint256 j = 0; j < pools.length; j++) {
                try GTXMarketMakerVault(pools[j]).redeemRewards() {
                    console.log("%s claimed rewards from %s", name, poolNames[j]);
                } catch {
                    console.log("%s failed to claim rewards from %s", name, poolNames[j]);
                }
            }
            
            vm.stopPrank();
            
            uint256 finalBalance = token.balanceOf(voter);
            uint256 rewards = finalBalance - initialBalance;
            
            console.log("%s received %d tokens in rewards", name, rewards / 1e18);
        }
    }
    
    function addVoter(string memory name, address addr) private {
        voters.push(addr);
        voterNames.push(name);
        console.log("Added voter: %s (%s)", name, addr);
    }
    
    function startsWith(string memory str, string memory prefix) private pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (strBytes.length < prefixBytes.length) {
            return false;
        }
        
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        
        return true;
    }
}
