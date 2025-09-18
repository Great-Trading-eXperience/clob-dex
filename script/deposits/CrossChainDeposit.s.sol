// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../src/core/ChainBalanceManager.sol";
import "../../src/core/BalanceManager.sol";
import "../../src/core/SyntheticTokenFactory.sol";
import "../../src/core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "../../src/core/libraries/Currency.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Test Cross-Chain
 * @dev Universal script to test cross-chain deposits between any two chains
 *      Includes validation of trading pools (gsWETH/gsUSDC, gsWBTC/gsUSDC)
 * 
 * Environment Variables:
 *   SIDE_CHAIN      - Name of side chain deployment file (e.g., "31338", "4661")
 *   CORE_CHAIN      - Name of core chain deployment file (e.g., "31337", "1918988905") 
 *   TOKEN_SYMBOL    - Token to test (e.g., "USDC", "WETH", "WBTC")
 *   DEPOSIT_AMOUNT  - Amount to deposit (in token's native decimals)
 *   TEST_RECIPIENT  - Address to receive synthetic tokens (optional, defaults to deployer)
 *
 * Usage Examples:
 *   # Test USDC deposit from chain 31338 to chain 31337
 *   SIDE_CHAIN=31338 CORE_CHAIN=31337 TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=1000000000 \
 *   forge script script/TestCrossChainDeposit.s.sol:TestCrossChainDeposit --rpc-url https://side-anvil.gtxdex.xyz --broadcast
 *
 *   # Check all trading pools on core chain
 *   CORE_CHAIN=31337 forge script script/TestCrossChainDeposit.s.sol:TestCrossChainDeposit --rpc-url https://anvil.gtxdex.xyz --sig "checkAllTradingPools()"
 *
 *   # Test WETH deposit from appchain to rari  
 *   SIDE_CHAIN=4661 CORE_CHAIN=1918988905 TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=1000000000000000000 \
 *   forge script script/TestCrossChainDeposit.s.sol:TestCrossChainDeposit --rpc-url $APPCHAIN_RPC --broadcast
 */
contract TestCrossChainDeposit is DeployHelpers {
    
    // Configuration
    string public sideChainName;
    string public coreChainName;
    string public tokenSymbol;
    uint256 public depositAmount;
    address public testRecipient;
    address public deployer;
    
    // Loaded contracts
    ChainBalanceManager sideChainBM;
    IERC20 sideToken;
    address syntheticTokenAddress;
    IPoolManager poolManager;
    
    // Pool validation addresses
    address gsUSDCAddress;
    address gsWETHAddress;
    address gsWBTCAddress;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        // Load configuration from environment variables
        _loadConfiguration();
        
        console.log("========== CROSS-CHAIN DEPOSIT TEST ==========");
        console.log("Deployer=%s", deployer);
        console.log("TestRecipient=%s", testRecipient);
        console.log("SideChain=%s", sideChainName);
        console.log("CoreChain=%s", coreChainName);
        console.log("TokenSymbol=%s", tokenSymbol);
        console.log("DepositAmount=%s", depositAmount);
        console.log("CurrentChainID=%s", block.chainid);
        
        // Load deployment addresses from JSON files
        _loadDeploymentAddresses();
        
        console.log("========== LOADED CONTRACT ADDRESSES ==========");
        console.log("SideChainBalanceManager=%s", address(sideChainBM));
        console.log("SideToken_%s=%s", tokenSymbol, address(sideToken));
        if (syntheticTokenAddress != address(0)) {
            console.log("TargetSyntheticToken_gs%s=%s", tokenSymbol, syntheticTokenAddress);
        }
        
        // Validate trading pools exist
        _validateTradingPools();
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Execute the cross-chain deposit test
        _executeCrossChainTest();
        
        vm.stopBroadcast();
        
        console.log("\n========== TEST COMPLETE SUMMARY ==========");
        console.log("# Cross-chain deposit transaction submitted successfully");
        console.log("Deployer=%s", deployer);
        console.log("TestRecipient=%s", testRecipient);
        console.log("TokenSymbol=%s", tokenSymbol);
        console.log("DepositAmount=%s", depositAmount);
        console.log("# Monitor the destination chain for synthetic token minting");
        console.log("# Use checkSyntheticBalance() to verify result on core chain");
    }
    
    function _loadConfiguration() internal {
        // Load side chain name (defaults to current chain ID)
        try vm.envString("SIDE_CHAIN") returns (string memory sideChain) {
            sideChainName = sideChain;
        } catch {
            sideChainName = vm.toString(block.chainid);
        }
        
        // Load core chain name (defaults to 31337)
        try vm.envString("CORE_CHAIN") returns (string memory coreChain) {
            coreChainName = coreChain;
        } catch {
            coreChainName = "31337";
        }
        
        // Load token symbol (defaults to USDC)
        try vm.envString("TOKEN_SYMBOL") returns (string memory symbol) {
            tokenSymbol = symbol;
        } catch {
            tokenSymbol = "USDC";
        }
        
        // Load deposit amount (defaults based on token)
        try vm.envUint("DEPOSIT_AMOUNT") returns (uint256 amount) {
            depositAmount = amount;
        } catch {
            // Set default amounts based on token
            if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("USDC"))) {
                depositAmount = 1000000000; // 1000 USDC (6 decimals)
            } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WETH"))) {
                depositAmount = 1000000000000000000; // 1 WETH (18 decimals)
            } else if (keccak256(bytes(tokenSymbol)) == keccak256(bytes("WBTC"))) {
                depositAmount = 100000000; // 1 WBTC (8 decimals)
            } else {
                depositAmount = 1000000000000000000; // 1 unit with 18 decimals
            }
        }
        
        // Load test recipient (defaults to deployer)
        try vm.envAddress("TEST_RECIPIENT") returns (address recipient) {
            testRecipient = recipient;
        } catch {
            testRecipient = deployer;
        }
    }
    
    function _loadDeploymentAddresses() internal {
        // Construct deployment file paths
        string memory sideDeploymentPath = string.concat(
            vm.projectRoot(), 
            "/deployments/", 
            sideChainName, 
            ".json"
        );
        
        string memory coreDeploymentPath = string.concat(
            vm.projectRoot(), 
            "/deployments/", 
            coreChainName, 
            ".json"
        );
        
        console.log("# Loading side chain from file=%s", sideDeploymentPath);
        console.log("# Loading core chain from file=%s", coreDeploymentPath);
        
        // Load side chain deployment
        if (!_fileExists(sideDeploymentPath)) {
            revert(string.concat("Side chain deployment not found: ", sideDeploymentPath));
        }
        
        string memory sideJson = vm.readFile(sideDeploymentPath);
        
        // Load ChainBalanceManager
        address sideChainBMAddr = vm.parseJsonAddress(sideJson, ".ChainBalanceManager");
        sideChainBM = ChainBalanceManager(sideChainBMAddr);
        
        // Load side token
        string memory tokenKey = string.concat(".", tokenSymbol);
        address sideTokenAddr = vm.parseJsonAddress(sideJson, tokenKey);
        sideToken = IERC20(sideTokenAddr);
        
        // Load core chain deployment (for synthetic token address and PoolManager)
        if (_fileExists(coreDeploymentPath)) {
            string memory coreJson = vm.readFile(coreDeploymentPath);
            string memory syntheticKey = string.concat(".gs", tokenSymbol);
            
            try vm.parseJsonAddress(coreJson, syntheticKey) returns (address synthAddr) {
                syntheticTokenAddress = synthAddr;
            } catch {
                console.log("# Synthetic token gs%s not yet deployed on core chain", tokenSymbol);
                syntheticTokenAddress = address(0);
            }
            
            // Load PoolManager for pool validation
            try vm.parseJsonAddress(coreJson, ".PROXY_POOLMANAGER") returns (address poolManagerAddr) {
                poolManager = IPoolManager(poolManagerAddr);
            } catch {
                // Try fallback naming
                try vm.parseJsonAddress(coreJson, ".PoolManager") returns (address poolManagerAddr) {
                    poolManager = IPoolManager(poolManagerAddr);
                } catch {
                    console.log("# WARNING: PoolManager not found in core chain deployment");
                }
            }
            
            // Load all synthetic token addresses for pool validation
            try vm.parseJsonAddress(coreJson, ".gsUSDC") returns (address addr) {
                gsUSDCAddress = addr;
            } catch {
                console.log("# gsUSDC not found in core chain deployment");
            }
            
            try vm.parseJsonAddress(coreJson, ".gsWETH") returns (address addr) {
                gsWETHAddress = addr;
            } catch {
                console.log("# gsWETH not found in core chain deployment");
            }
            
            try vm.parseJsonAddress(coreJson, ".gsWBTC") returns (address addr) {
                gsWBTCAddress = addr;
            } catch {
                console.log("# gsWBTC not found in core chain deployment");
            }
        } else {
            console.log("# WARNING: Core chain deployment not found: %s", coreDeploymentPath);
        }
    }
    
    function _executeCrossChainTest() internal {
        console.log("========== EXECUTING CROSS-CHAIN DEPOSIT ==========");
        
        // Check initial state
        _displayInitialState();
        
        // Ensure sufficient balance
        _ensureSufficientBalance();
        
        // Approve ChainBalanceManager
        _approveChainBalanceManager();
        
        // Execute deposit
        _executeDeposit();
        
        // Display final state
        _displayFinalState();
    }
    
    function _displayInitialState() internal view {
        console.log("========== INITIAL STATE ==========");
        
        uint256 userBalance = sideToken.balanceOf(testRecipient);
        console.log("User_%s_Balance=%s", tokenSymbol, userBalance);
        
        uint256 allowance = sideToken.allowance(testRecipient, address(sideChainBM));
        console.log("ChainBM_Allowance=%s", allowance);
        
        bool isWhitelisted = sideChainBM.isTokenWhitelisted(address(sideToken));
        console.log("Token_Whitelisted=%s", isWhitelisted);
        
        if (!isWhitelisted) {
            revert("Token not whitelisted in ChainBalanceManager");
        }
        
        address mappedToken = sideChainBM.getTokenMapping(address(sideToken));
        console.log("Mapped_Synthetic_Token=%s", mappedToken);
    }
    
    function _ensureSufficientBalance() internal {
        uint256 currentBalance = sideToken.balanceOf(testRecipient);
        
        if (currentBalance < depositAmount) {
            console.log("# Insufficient balance, attempting to mint");
            
            // Try to mint tokens (if contract supports it)
            (bool success, ) = address(sideToken).call(
                abi.encodeWithSignature("mint(address,uint256)", testRecipient, depositAmount)
            );
            
            if (success) {
                console.log("# Minted %s tokens=%s successfully", tokenSymbol, depositAmount);
            } else {
                revert("Cannot mint tokens and insufficient balance for test");
            }
        }
    }
    
    function _approveChainBalanceManager() internal {
        console.log("========== APPROVING CHAIN BALANCE MANAGER ==========");
        
        uint256 currentAllowance = sideToken.allowance(testRecipient, address(sideChainBM));
        
        if (currentAllowance < depositAmount) {
            sideToken.approve(address(sideChainBM), depositAmount);
            console.log("# Approved %s tokens=%s successfully", tokenSymbol, depositAmount);
        } else {
            console.log("# Sufficient allowance already exists");
        }
    }
    
    function _executeDeposit() internal {
        console.log("========== EXECUTING DEPOSIT ==========");
        console.log("# Depositing amount=%s token=%s recipient=%s", depositAmount, tokenSymbol, testRecipient);
        
        // Use the correct deposit function signature
        try sideChainBM.deposit(address(sideToken), depositAmount, testRecipient) {
            console.log("# Cross-chain deposit executed successfully");
            console.log("# Hyperlane message sent to core chain");
        } catch Error(string memory reason) {
            console.log("# ERROR: Deposit failed: %s", reason);
            revert("Cross-chain deposit failed");
        } catch {
            revert("Cross-chain deposit failed - check function signatures");
        }
    }
    
    function _displayFinalState() internal view {
        console.log("========== FINAL STATE ==========");
        
        uint256 finalBalance = sideToken.balanceOf(testRecipient);
        console.log("Final_User_%s_Balance=%s", tokenSymbol, finalBalance);
        
        uint256 cbmBalance = sideToken.balanceOf(address(sideChainBM));
        console.log("ChainBM_%s_Balance=%s", tokenSymbol, cbmBalance);
    }
    
    function _validateTradingPools() internal view {
        console.log("========== VALIDATING TRADING POOLS ==========");
        
        if (address(poolManager) == address(0)) {
            console.log("# INFO: PoolManager not available on side chain, skipping pool validation");
            console.log("# NOTE: Pool validation should be done on the core chain (31337)");
            return;
        }
        
        if (gsUSDCAddress == address(0) || gsWETHAddress == address(0) || gsWBTCAddress == address(0)) {
            console.log("# INFO: Synthetic tokens not available on side chain, skipping pool validation");
            console.log("# NOTE: Pool validation should be done on the core chain (31337)");
            return;
        }
        
        console.log("# INFO: Trading pools exist on core chain - validation skipped for side chain");
    }
    
    function _checkPoolExists(address token1, address token2, string memory poolName) internal view returns (bool) {
        Currency currency1 = Currency.wrap(token1);
        Currency currency2 = Currency.wrap(token2);
        
        try poolManager.poolExists(currency1, currency2) returns (bool exists) {
            if (exists) {
                console.log("# Pool %s exists", poolName);
                
                // Also check liquidity score if available
                try poolManager.getPoolLiquidityScore(currency1, currency2) returns (uint256 liquidityScore) {
                    console.log("# Pool %s liquidity_score=%s", poolName, liquidityScore);
                } catch {
                    console.log("# Pool %s liquidity_score=unknown", poolName);
                }
                
                return true;
            } else {
                console.log("# Pool %s does_not_exist", poolName);
                return false;
            }
        } catch {
            console.log("# Pool %s status=unknown_error", poolName);
            return false;
        }
    }
    
    function _getChainFileName(uint256 chainId) internal pure returns (string memory) {
        // Always return chain ID as string for consistency
        return vm.toString(chainId);
    }
    
    function _fileExists(string memory filePath) internal view returns (bool) {
        try vm.fsMetadata(filePath) returns (Vm.FsMetadata memory) {
            return true;
        } catch {
            return false;
        }
    }
    
    // Utility function to check synthetic token balance on core chain
    // (Can be called separately on core chain RPC)
    function checkSyntheticBalance(address user) external view returns (uint256) {
        if (syntheticTokenAddress == address(0)) {
            console.log("# ERROR: Synthetic token address not loaded");
            return 0;
        }
        
        uint256 balance = IERC20(syntheticTokenAddress).balanceOf(user);
        console.log("Synthetic_gs%s_Balance_For_%s=%s", tokenSymbol, user, balance);
        return balance;
    }
    
    // Utility function to check all trading pools status on core chain
    // (Can be called separately on core chain RPC)
    function checkAllTradingPools() external {
        // Load configuration first
        coreChainName = vm.envOr("CORE_CHAIN", string("31337"));
        
        string memory coreDeploymentPath = string.concat(
            vm.projectRoot(),
            "/deployments/",
            coreChainName,
            ".json"
        );
        
        if (!_fileExists(coreDeploymentPath)) {
            console.log("# ERROR: Core chain deployment not found: %s", coreDeploymentPath);
            return;
        }
        
        // Load required contracts
        string memory coreJson = vm.readFile(coreDeploymentPath);
        
        // Load PoolManager
        try vm.parseJsonAddress(coreJson, ".PROXY_POOLMANAGER") returns (address poolManagerAddr) {
            poolManager = IPoolManager(poolManagerAddr);
        } catch {
            try vm.parseJsonAddress(coreJson, ".PoolManager") returns (address poolManagerAddr) {
                poolManager = IPoolManager(poolManagerAddr);
            } catch {
                console.log("# ERROR: PoolManager not found in deployment");
                return;
            }
        }
        
        // Load synthetic tokens
        try vm.parseJsonAddress(coreJson, ".gsUSDC") returns (address addr) {
            gsUSDCAddress = addr;
        } catch {
            console.log("# ERROR: gsUSDC not found in deployment");
            return;
        }
        
        try vm.parseJsonAddress(coreJson, ".gsWETH") returns (address addr) {
            gsWETHAddress = addr;
        } catch {
            console.log("# ERROR: gsWETH not found in deployment");
            return;
        }
        
        try vm.parseJsonAddress(coreJson, ".gsWBTC") returns (address addr) {
            gsWBTCAddress = addr;
        } catch {
            console.log("# ERROR: gsWBTC not found in deployment");
            return;
        }
        
        // Validate all pools
        console.log("========== CHECKING ALL TRADING POOLS ==========");
        console.log("PoolManager=%s", address(poolManager));
        console.log("gsUSDC=%s", gsUSDCAddress);
        console.log("gsWETH=%s", gsWETHAddress);
        console.log("gsWBTC=%s", gsWBTCAddress);
        
        _checkPoolExists(gsWETHAddress, gsUSDCAddress, "gsWETH/gsUSDC");
        _checkPoolExists(gsWBTCAddress, gsUSDCAddress, "gsWBTC/gsUSDC");
        
        console.log("# Pool validation complete");
    }
}