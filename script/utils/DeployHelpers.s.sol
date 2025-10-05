//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";

contract DeployHelpers is Script {
    error InvalidChain();
    error InvalidPrivateKey(string);

    struct Deployment {
        string name;
        address addr;
    }

    struct DeployedContract {
        address addr;
        bool isSet;
    }

    string root;
    string path;
    Deployment[] public deployments;

    mapping(string => DeployedContract) public deployed;

    function setupLocalhostEnv() internal returns (uint256 localhostPrivateKey) {
        // if (block.chainid == 31_337) {
        //     root = vm.projectRoot();
        //     path = string.concat(root, "/localhost.json");
        //     string memory json = vm.readFile(path);
        //     bytes memory mnemonicBytes = vm.parseJson(json, ".wallet.mnemonic");
        //     string memory mnemonic = abi.decode(mnemonicBytes, (string));
        //     return vm.deriveKey(mnemonic, 0);
        // } else {
            return vm.envUint("PRIVATE_KEY");
        // }
    }
    
    function getDeployerKey() internal returns (uint256 deployerPrivateKey) {
        deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }
    }

    function getDeployerKey2() internal returns (uint256 deployerPrivateKey) {
        deployerPrivateKey =  vm.envUint("PRIVATE_KEY_2");
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }
    }

    function loadDeployments() internal virtual {
        root = vm.projectRoot();
        path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        // Check if deployments file exists
        if (!fileExists(path)) {
            console.log("No existing deployments found for chain %s", chainIdStr);
            return;
        }

        try vm.readFile(path) returns (string memory json) {
            // Get all keys in the JSON file
            string[] memory keys = vm.parseJsonKeys(json, "$");

            console.log("Loading %d existing deployments from %s", keys.length - 1, path); // -1 for networkName

            for (uint256 i = 0; i < keys.length; i++) {
                string memory contractName = keys[i];

                // Skip networkName
                if (keccak256(bytes(contractName)) == keccak256(bytes("networkName"))) {
                    continue;
                }

                // Use proper JSON path format with a dot prefix
                string memory jsonPath = string.concat(".", contractName);
                bytes memory addrBytes = vm.parseJson(json, jsonPath);
                address addr = abi.decode(addrBytes, (address));

                // Store in deployed mapping with contract name as key
                deployed[contractName] = DeployedContract(addr, true);

                // Also add to the deployments array
                deployments.push(Deployment(contractName, addr));

                console.log("Loaded %s: %s", contractName, addr);
            }
        } catch {
            console.log("Error loading existing deployments");
        }
    }

    function exportDeployments() internal virtual {
        Chain memory chain = Chain({name: "Rise", chainId: 11_155_931, chainAlias: "riseSepolia", rpcUrl: ""});
        setChain("riseSepolia", chain);

        chain = Chain({name: "Pharos", chainId: 50_002, chainAlias: "pharos", rpcUrl: ""});
        setChain("pharos", chain);

        chain = Chain({name: "GTX", chainId: 31_338, chainAlias: "gtxCoreDevnet", rpcUrl: ""});
        setChain("gtxCoreDevnet", chain);

        // fetch already existing contracts
        root = vm.projectRoot();
        path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));

        string memory jsonWrite;

        uint256 len = deployments.length;
        console.log("Exporting %d deployments to JSON", deployments.length);

        for (uint256 i = 0; i < len; i++) {
            console.log("Set---", vm.toString(deployments[i].addr), deployments[i].name);
            vm.serializeString(jsonWrite, deployments[i].name, vm.toString(deployments[i].addr));
        }

        string memory chainName = "default_network";

        // try this.getChain() returns (Chain memory chain) {
        //     chainName = chain.name;
        // } catch {
        //     chainName = findChainName();
        // }

        jsonWrite = vm.serializeString(jsonWrite, "networkName", chainName);
        vm.writeJson(jsonWrite, path);

        console.log("\nDeployment data written to: %s", path);
    }

    function getChain() public returns (Chain memory) {
        return getChain(block.chainid);
    }

    function findChainName() public returns (string memory) {
        uint256 thisChainId = block.chainid;
        string[2][] memory allRpcUrls = vm.rpcUrls();
        for (uint256 i = 0; i < allRpcUrls.length; i++) {
            try vm.createSelectFork(allRpcUrls[i][1]) {
                if (block.chainid == thisChainId) {
                    return allRpcUrls[i][0];
                }
            } catch {
                continue;
            }
        }
        revert InvalidChain();
    }

    function fileExists(
        string memory filePath
    ) internal view returns (bool) {
        try vm.fsMetadata(filePath) returns (Vm.FsMetadata memory) {
            return true;
        } catch {
            return false;
        }
    }
}
