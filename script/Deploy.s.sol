// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/BalanceManager.sol";
import "../src/PoolManager.sol";
import "../src/GTXRouter.sol";
import {Swap} from "./Swap.s.sol";
import {IOrderBook} from "../src/interfaces/IOrderBook.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {CreateMockPools} from "./CreateMockPools.s.sol";

contract Deploy is Script {
    // Contract instances
    BalanceManager public balanceManager;
    PoolManager public poolManager;
    GTXRouter public router;

    // Deployment parameters
    address public owner;
    string public chainId;
    uint256 private deployerPrivateKey;

    // Environment flags
    bool public shouldCreatePools;
    bool public shouldRunSwap;

    function run() public {
        // Setup common parameters
        chainId = vm.envString("CHAIN_ID");
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);

        // Read environment flags
        shouldCreatePools = vm.envOr("CREATE_POOLS", false);
        shouldRunSwap = vm.envOr("RUN_SWAP", false);

        // Deploy is always executed
        deployContracts();

        //NOTE: Remove existing .env for create new tokens

        if (shouldCreatePools) {
            runCreatePools();
        }

        if (shouldRunSwap) {
            runSwapTest();
        }
    }

    function runCreatePools() public {
        vm.setEnv("POOL_MANAGER_ADDRESS", vm.toString(address(poolManager)));
        CreateMockPools poolCreator = new CreateMockPools();
        poolCreator.run();
    }

    function deployContracts() public {
        console.log("Deploying core contracts...");

        // Begin deployment
        vm.startBroadcast(deployerPrivateKey);

        // Contract deployment parameters
        uint256 feeMaker = 1; // Example fee maker value
        uint256 feeTaker = 3; // Example fee taker value

        // Deploy core contracts
        balanceManager = new BalanceManager(owner, owner, feeMaker, feeTaker);
        console.log("BalanceManager deployed at:", address(balanceManager));

        poolManager = new PoolManager(owner, address(balanceManager));
        console.log("PoolManager deployed at:", address(poolManager));

        router = new GTXRouter(address(poolManager), address(balanceManager));
        console.log("GTXRouter deployed at:", address(router));

        // Configure contracts
        balanceManager.setAuthorizedOperator(address(poolManager), true);
        balanceManager.transferOwnership(address(poolManager));
        poolManager.setRouter(address(router));

        vm.stopBroadcast();
        console.log("Core contracts deployed and configured successfully");

        // Set environment variables for core contracts
        string memory envPrefix = string.concat(chainId, "_");
        vm.setEnv(string.concat(envPrefix, "BALANCE_MANAGER"), vm.toString(address(balanceManager)));
        vm.setEnv(string.concat(envPrefix, "POOL_MANAGER"), vm.toString(address(poolManager)));
        vm.setEnv(string.concat(envPrefix, "ROUTER"), vm.toString(address(router)));

        updateEnvFile();
    }

    function updateEnvFile() internal {
        string memory envPath = ".env";

        // Check if .env file exists and read its content
        string memory existingEnv = "";
        if (vm.exists(envPath)) {
            existingEnv = vm.readFile(envPath);
            // Check if the file ends with a newline
            bytes memory existingEnvBytes = bytes(existingEnv);
            if (
                existingEnvBytes.length > 0 && existingEnvBytes[existingEnvBytes.length - 1] != 0x0A
            ) {
                existingEnv = string.concat(existingEnv, "\n");
            }
        }

        // Create a comment for the added variables
        string memory comment = string.concat(
            "\n# Core contract addresses for chain ",
            chainId,
            " - Added on ",
            vm.toString(block.timestamp),
            "\n"
        );

        // Prepare contract address variables
        string memory envUpdates = string.concat(
            chainId,
            "_BALANCE_MANAGER=",
            vm.toString(address(balanceManager)),
            "\n",
            chainId,
            "_POOL_MANAGER=",
            vm.toString(address(poolManager)),
            "\n",
            chainId,
            "_ROUTER=",
            vm.toString(address(router)),
            "\n"
        );

        // Write back the updated content
        vm.writeFile(envPath, string.concat(existingEnv, comment, envUpdates));
        console.log("Updated .env file with core contract addresses");
    }

    function runSwapTest() public {
        console.log("Running swap test...");

        // Execute swap script to test engine functionality
        Swap swap = new Swap(address(balanceManager), address(poolManager), address(router));
        swap.run();

        console.log("Swap test completed");
    }
}
