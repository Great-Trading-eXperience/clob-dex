/*
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/PoolManager.sol";
import "../src/BalanceManager.sol";
import "../src/mocks/MockToken.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";

contract CreateMockPools is Script {
    // Contract instances
    PoolManager public poolManager;

    // Deployment parameters
    address public owner;
    string public chainId;
    uint256 private deployerPrivateKey;

    // Token parameters
    string[5] private tokenNames =
        ["Wrapped Ether", "Wrapped Bitcoin", "Chainlink", "Trump", "Dogecoin"];
    string[5] private tokenSymbols = ["WETH", "WBTC", "LINK", "TRUMP", "DOGE"];
    uint8[5] private tokenDecimals = [18, 8, 18, 18, 8];

    // Environment tracking
    bool private deployedNewTokens = false;
    string private envUpdates = "";

    function run() public {
        // Setup execution environment
        setupEnvironment();
        createPools();
    }

    function setupEnvironment() private {
        chainId = vm.envString("CHAIN_ID");
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);

        address poolManagerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");
        poolManager = PoolManager(poolManagerAddress);

        console.log("Environment setup complete");
    }

    function createPools() public {
        console.log("Creating pools...");
        vm.startBroadcast(deployerPrivateKey);

        // Setup tokens
        address usdc = setupUSDC();
        address[] memory tokens = setupTokens();

        // Configure pool manager
        setupPoolManager(usdc, tokens);

        vm.stopBroadcast();
        console.log("Pools created successfully");

        // Update environment if new tokens were deployed
        if (deployedNewTokens) {
            updateEnvironment(usdc, tokens);
        }
    }

    function setupUSDC() private returns (address usdc) {
        string memory usdcEnvVar = string.concat("USDC_", chainId, "_ADDRESS");

        try vm.envAddress(usdcEnvVar) returns (address envUsdc) {
            usdc = envUsdc;
            console.log("Using existing USDC from environment:", usdc);
        } catch {
            // Deploy mock USDC
            MockToken mockUsdc = new MockToken("USD Coin", "USDC", 6);
            usdc = address(mockUsdc);
            mockUsdc.mint(owner, 1_000_000 * 10 ** 6);
            console.log("Deployed mock USDC at:", usdc);

            // Track for environment update
            deployedNewTokens = true;
            envUpdates = string.concat(envUpdates, usdcEnvVar, "=", vm.toString(usdc), "\n");
        }

        return usdc;
    }

    function setupTokens() private returns (address[] memory tokens) {
        tokens = new address[](5);

        for (uint256 i = 0; i < tokens.length; ++i) {
            string memory symbol = tokenSymbols[i];
            string memory tokenEnvVar = string.concat(symbol, "_", chainId, "_ADDRESS");

            console.log(tokenEnvVar);

            try vm.envAddress(tokenEnvVar) returns (address envToken) {
                tokens[i] = envToken;
                console.log(
                    string.concat("Using existing ", symbol, " from environment:"), tokens[i]
                );
            } catch {
                // Deploy mock token
                MockToken mockToken = new MockToken(tokenNames[i], symbol, tokenDecimals[i]);
                tokens[i] = address(mockToken);
                console.log(string.concat("Deployed mock ", symbol, " at:"), tokens[i]);

                // Mint test tokens
                uint256 mintAmount = 100 * 10 ** uint256(tokenDecimals[i]);
                mockToken.mint(owner, mintAmount);

                // Track for environment update
                deployedNewTokens = true;
                envUpdates =
                    string.concat(envUpdates, tokenEnvVar, "=", vm.toString(tokens[i]), "\n");
            }
        }

        return tokens;
    }

    function setupPoolManager(address usdc, address[] memory tokens) private {
        // Add USDC as common intermediary
        poolManager.addCommonIntermediary(Currency.wrap(usdc));
        console.log("Added USDC as common intermediary:", usdc);

        // Create pools for each token with USDC
        Currency quoteCurrency = Currency.wrap(usdc);
        for (uint256 i = 0; i < tokens.length; ++i) {
            Currency baseCurrency = Currency.wrap(tokens[i]);

            // Define trading rules based on token decimals
            IOrderBook.TradingRules memory rules;

            if (tokenDecimals[i] == 8) {
                // Rules for 8 decimal tokens (BTC, DOGE)
                rules = IOrderBook.TradingRules({
                    minTradeAmount: Quantity.wrap(uint128(1e3)), // 0.00001 BTC (8 decimals)
                    minAmountMovement: Quantity.wrap(uint128(1e2)), // 0.000001 BTC (8 decimals)
                    minOrderSize: Quantity.wrap(uint128(2e4)), // 0.02 USDC (6 decimals)
                    minPriceMovement: Quantity.wrap(uint128(1e5)), // 0.1 USDC (6 decimals)
                    slippageTreshold: 15 // 15%
                });
                console.log("Applied 8 decimal trading rules for:", tokenSymbols[i]);
            } else {
                // Default rules for 18 decimal tokens (ETH, LINK, TRUMP)
                rules = IOrderBook.TradingRules({
                    minTradeAmount: Quantity.wrap(uint128(1e14)), // 0.0001 ETH (18 decimals)
                    minAmountMovement: Quantity.wrap(uint128(1e13)), // 0.00001 ETH (18 decimals)
                    minOrderSize: Quantity.wrap(uint128(1e4)), // 0.01 USDC (6 decimals)
                    minPriceMovement: Quantity.wrap(uint128(1e4)), // 0.01 USDC (6 decimals)
                    slippageTreshold: 20 // 20%
                });
                console.log("Applied 18 decimal trading rules for:", tokenSymbols[i]);
            }

            poolManager.createPool(baseCurrency, quoteCurrency, rules);
            console.log("Pool created for token:", tokens[i]);
        }
    }

    function updateEnvironment(address usdc, address[] memory tokens) private {
        // Update .env file
        updateEnvFile();

        // Update VM environment variables
        setEnvironmentVariables(usdc, tokens);
    }

    function updateEnvFile() private {
        string memory envPath = ".env";
        string memory existingEnv = "";

        // Read existing .env content if available
        if (vm.exists(envPath)) {
            existingEnv = vm.readFile(envPath);
            // Ensure file ends with newline
            bytes memory existingEnvBytes = bytes(existingEnv);
            if (
                existingEnvBytes.length > 0 && existingEnvBytes[existingEnvBytes.length - 1] != 0x0A
            ) {
                existingEnv = string.concat(existingEnv, "\n");
            }
        }

        // Add comment header for new variables
        string memory comment = string.concat(
            "\n# Token addresses for chain ",
            chainId,
            " - Added on ",
            vm.toString(block.timestamp),
            "\n"
        );

        // Write updated content
        vm.writeFile(envPath, string.concat(existingEnv, comment, envUpdates));
        console.log("Updated .env file with newly deployed token addresses");
    }

    function setEnvironmentVariables(address usdc, address[] memory tokens) private {
        // Set USDC environment variable
        string memory usdcEnvVar = string.concat("USDC_", chainId, "_ADDRESS");
        vm.setEnv(usdcEnvVar, vm.toString(usdc));
        console.log("Set environment variable:", usdcEnvVar, "=", vm.toString(usdc));

        // Set token environment variables
        for (uint256 i = 0; i < tokens.length; ++i) {
            string memory tokenEnvVar = string.concat(tokenSymbols[i], "_", chainId, "_ADDRESS");
            vm.setEnv(tokenEnvVar, vm.toString(tokens[i]));
            console.log("Set environment variable:", tokenEnvVar, "=", vm.toString(tokens[i]));
        }

        console.log("Environment variables set for subsequent script executions");
    }
}
*/
