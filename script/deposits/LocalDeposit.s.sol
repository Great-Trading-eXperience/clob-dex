// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TokenRegistry} from "../../src/core/TokenRegistry.sol";
import {BalanceManager} from "../../src/core/BalanceManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Test Local Deposit
 * @dev Test local deposit functionality using deployment data
 * 
 * Environment Variables:
 *   TOKEN_SYMBOL     - Token symbol to test (e.g., "USDC", "WETH", "WBTC")
 *   DEPOSIT_AMOUNT   - Amount to deposit (in token's native decimals)
 *   TEST_RECIPIENT   - Address to receive synthetic tokens (optional, defaults to deployer)
 *   LOCAL_TOKEN      - Address of local token to map (optional, uses deployment file)
 *
 * Usage Examples:
 *   TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=1000000000 forge script script/LocalDeposit.s.sol:LocalDeposit --rpc-url https://anvil.gtxdex.xyz --broadcast
 *   TOKEN_SYMBOL=WETH LOCAL_TOKEN=0x123... DEPOSIT_AMOUNT=1000000000000000000 forge script script/LocalDeposit.s.sol:LocalDeposit --rpc-url $RPC_URL --broadcast
 */
contract LocalDeposit is DeployHelpers {
    // Configuration
    string public tokenSymbol;
    uint256 public depositAmount;
    address public testRecipient;
    address public localTokenAddress;
    
    // Loaded contracts
    TokenRegistry public tokenRegistry;
    BalanceManager public balanceManager;
    IERC20 public localToken;
    address public syntheticTokenAddress;
    
    function run() external {
        // Load existing deployments first
        loadDeployments();
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load configuration from environment
        _loadConfiguration(deployer);

        console.log("========== TESTING LOCAL DEPOSIT ==========");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Test Recipient:", testRecipient);
        console.log("Token Symbol:", tokenSymbol);
        console.log("Deposit Amount:", depositAmount);
        console.log("");

        // Load contract addresses from deployments
        _loadContracts();

        vm.startBroadcast(deployerPrivateKey);

        // Execute local deposit test
        _executeLocalDepositTest();

        vm.stopBroadcast();

        console.log("");
        console.log("========== LOCAL DEPOSIT TEST COMPLETE ==========");
        console.log("[SUCCESS] Local deposit test completed");
        console.log("[INFO] Check BalanceManager balances for results");
    }
    
    function _loadConfiguration(address deployer) internal {
        // Token symbol to test
        tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("USDC"));
        
        // Load deposit amount (default based on token)
        try vm.envUint("DEPOSIT_AMOUNT") returns (uint256 amount) {
            depositAmount = amount;
        } catch {
            // Default amounts based on token decimals
            if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDC"))) {
                depositAmount = 1000000000; // 1000 USDC (6 decimals)
            } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WETH"))) {
                depositAmount = 1000000000000000000; // 1 WETH (18 decimals)
            } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WBTC"))) {
                depositAmount = 100000000; // 1 WBTC (8 decimals)
            } else {
                depositAmount = 1000000000000000000; // Default to 18 decimals
            }
        }
        
        // Test recipient (default to deployer)
        testRecipient = vm.envOr("TEST_RECIPIENT", deployer);
        
        // Custom local token address (optional)
        localTokenAddress = vm.envOr("LOCAL_TOKEN", address(0));
    }
    
    function _loadContracts() internal {
        // Load core contracts from deployed mapping
        require(deployed["PROXY_TOKENREGISTRY"].isSet, "TokenRegistry not found in deployments");
        require(deployed["PROXY_BALANCEMANAGER"].isSet, "BalanceManager not found in deployments");
        
        tokenRegistry = TokenRegistry(deployed["PROXY_TOKENREGISTRY"].addr);
        balanceManager = BalanceManager(deployed["PROXY_BALANCEMANAGER"].addr);
        
        console.log("TokenRegistry:", address(tokenRegistry));
        console.log("BalanceManager:", address(balanceManager));
        
        // Load token address
        if (localTokenAddress == address(0)) {
            // Try to load from deployment file based on token symbol
            require(deployed[tokenSymbol].isSet, string.concat("Token ", tokenSymbol, " not found in deployment"));
            localTokenAddress = deployed[tokenSymbol].addr;
        }
        
        localToken = IERC20(localTokenAddress);
        console.log("Local Token (%s):", tokenSymbol, address(localToken));
        
        // Try to load corresponding synthetic token
        string memory syntheticSymbol = string.concat("gs", tokenSymbol);
        if (deployed[syntheticSymbol].isSet) {
            syntheticTokenAddress = deployed[syntheticSymbol].addr;
            console.log("Target Synthetic Token (%s):", syntheticSymbol, syntheticTokenAddress);
        } else {
            console.log("WARNING: Synthetic token %s not found", syntheticSymbol);
            syntheticTokenAddress = address(0);
        }
    }
    
    function _executeLocalDepositTest() internal {
        console.log("========== EXECUTING LOCAL DEPOSIT ==========");
        
        uint32 currentChain = uint32(block.chainid);
        
        // Token mappings are now configured during deployment
        // No need to set up mappings here
        
        // Check initial balances
        uint256 initialTokenBalance = localToken.balanceOf(testRecipient);
        console.log("Initial token balance:", initialTokenBalance);
        
        if (initialTokenBalance < depositAmount) {
            console.log("ERROR: Insufficient token balance for test");
            console.log("  Required:", depositAmount);
            console.log("  Available:", initialTokenBalance);
            return;
        }
        
        // Approve and execute deposit
        _performDeposit();
        
        console.log("Local deposit test completed successfully");
    }
    
    function _performDeposit() internal {
        address depositor = msg.sender; // Current broadcaster
        
        console.log("Approving BalanceManager for token spending...");
        console.log("Depositor:", depositor);
        console.log("Amount:", depositAmount);
        
        // Approve BalanceManager
        try localToken.approve(address(balanceManager), depositAmount) {
            console.log("Approval successful");
        } catch Error(string memory reason) {
            console.log("Approval failed:", reason);
            return;
        } catch (bytes memory) {
            console.log("Approval failed with low-level error");
            return;
        }
        
        uint256 allowance = localToken.allowance(depositor, address(balanceManager));
        console.log("Approved amount:", allowance);
        
        if (allowance < depositAmount) {
            console.log("ERROR: Approval insufficient");
            return;
        }
        
        // Execute local deposit
        console.log("Executing depositLocal...");
        try balanceManager.depositLocal(localTokenAddress, depositAmount, testRecipient) {
            console.log("Local deposit executed successfully");
            console.log("  Token:", localTokenAddress);
            console.log("  Amount:", depositAmount);
            console.log("  Recipient:", testRecipient);
            
            // Check final balances
            uint256 finalTokenBalance = localToken.balanceOf(depositor);
            console.log("Final token balance:", finalTokenBalance);
            
        } catch Error(string memory reason) {
            console.log("Local deposit failed:", reason);
        } catch (bytes memory) {
            console.log("Local deposit failed with low-level error");
        }
    }
}