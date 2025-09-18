// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script, console} from "forge-std/Script.sol";

import "../../src/core/ChainBalanceManager.sol";
import "../utils/DeployHelpers.s.sol";

/**
 * @title Deploy Side Chain Balance Manager
 * @dev Deploy Chain Balance Manager on the side chain (source chain for deposits)
 */
contract DeploySideChainBalanceManager is DeployHelpers {
    // Side chain configuration (configurable via environment)
    address public SIDE_MAILBOX;
    uint32 public SIDE_DOMAIN;
    string public SIDE_RPC;
    string public SIDE_NAME;
    
    address public CORE_MAILBOX;
    uint32 public CORE_DOMAIN;
    string public CORE_RPC;
    string public CORE_NAME;

    function run() external {
        // Load existing deployments first
        loadDeployments();
        
        // IMPORTANT: Store the original chain ID before any RPC switching
        uint256 originalChainId = block.chainid;
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load configuration
        _loadConfiguration();

        // Load core chain deployment file to get BalanceManager address
        address coreBalanceManager = _loadCoreChainBalanceManager();

        if (coreBalanceManager == address(0)) {
            revert("Core chain BalanceManager not found. Please deploy core chain first with: make deploy-core-chain-trading network=gtx_anvil");
        }

        console.log("========== DEPLOYING SIDE CHAIN BALANCE MANAGER ==========");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ChainBalanceManager (without cross-chain configuration)
        address chainBMAddress = _deployChainBalanceManagerOnly(deployer, coreBalanceManager);

        vm.stopBroadcast();

        // Configure cross-chain after broadcast (requires RPC switching)
        _configureBalanceManagerForCrossChain(coreBalanceManager, chainBMAddress);

        // Export deployments to JSON file (using original chain ID for correct file naming)
        exportDeployments(originalChainId);

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Deployment addresses saved to JSON file:");
        console.log("ChainBalanceManager=%s", chainBMAddress);
    }

    function exportDeployments() internal override {
        exportDeployments(block.chainid);
    }
    
    function exportDeployments(uint256 chainId) internal {
        // Use standard chain ID-based file naming
        string memory root = vm.projectRoot();
        string memory chainIdStr = vm.toString(chainId);
        string memory path = string.concat(root, "/deployments/", chainIdStr, ".json");

        string memory jsonWrite;
        uint256 len = deployments.length;

        for (uint256 i = 0; i < len; i++) {
            vm.serializeString(jsonWrite, deployments[i].name, vm.toString(deployments[i].addr));
        }

        string memory chainName = _getChainName(chainId);
        jsonWrite = vm.serializeString(jsonWrite, "networkName", chainName);
        vm.writeJson(jsonWrite, path);
    }

    function _loadCoreChainBalanceManager() internal returns (address) {
        // Try to get core chain name from environment, default to gtx-anvil
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        
        // Load core chain deployment file
        string memory root = vm.projectRoot();
        string memory coreDeploymentPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        try vm.readFile(coreDeploymentPath) returns (string memory jsonContent) {
            // Try different possible field names with env var support
            string memory balanceManagerKey = vm.envOr("BALANCE_MANAGER_KEY", string("PROXY_BALANCEMANAGER"));
            
            try vm.parseJsonAddress(jsonContent, string.concat(".", balanceManagerKey)) returns (address balanceManager) {
                return balanceManager;
            } catch {
                // Fallback to old naming
                try vm.parseJsonAddress(jsonContent, ".BalanceManager") returns (address balanceManager) {
                    return balanceManager;
                } catch {
                    return address(0);
                }
            }
        } catch {
            return address(0);
        }
    }

    function _loadConfiguration() internal {
        // Side chain configuration
        SIDE_MAILBOX = vm.envOr("SIDE_MAILBOX", 0x0E801D84Fa97b50751Dbf25036d067dCf18858bF);
        SIDE_DOMAIN = uint32(vm.envOr("SIDE_DOMAIN", uint256(31338)));
        
        // Handle string env vars differently
        try vm.envString("SIDE_RPC") returns (string memory rpc) {
            SIDE_RPC = rpc;
        } catch {
            SIDE_RPC = "https://side-anvil.gtxdex.xyz";
        }
        
        try vm.envString("SIDE_NAME") returns (string memory name) {
            SIDE_NAME = name;
        } catch {
            SIDE_NAME = "GTX Side Chain";
        }
        
        // Core chain configuration  
        CORE_MAILBOX = vm.envOr("CORE_MAILBOX", 0xC9a43158891282A2B1475592D5719c001986Aaec);
        CORE_DOMAIN = uint32(vm.envOr("CORE_DOMAIN", uint256(31337)));
        
        try vm.envString("CORE_RPC") returns (string memory rpc) {
            CORE_RPC = rpc;
        } catch {
            CORE_RPC = "https://anvil.gtxdex.xyz";
        }
        
        try vm.envString("CORE_NAME") returns (string memory name) {
            CORE_NAME = name;
        } catch {
            CORE_NAME = "GTX Core Chain";
        }
    }

    function _deployChainBalanceManagerOnly(address owner, address destinationBalanceManager) internal returns (address) {
        // Deploy ChainBalanceManager
        ChainBalanceManager chainBMImpl = new ChainBalanceManager();
        deployments.push(Deployment("ChainBalanceManager_Implementation", address(chainBMImpl)));
        deployed["ChainBalanceManager_Implementation"] = DeployedContract(address(chainBMImpl), true);

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint32,address)",
            owner, // owner
            SIDE_MAILBOX, // mailbox
            CORE_DOMAIN, // destinationDomain
            destinationBalanceManager // destinationBalanceManager
        );

        ERC1967Proxy chainBMProxy = new ERC1967Proxy(address(chainBMImpl), initData);
        ChainBalanceManager chainBM = ChainBalanceManager(address(chainBMProxy));
        deployments.push(Deployment("ChainBalanceManager", address(chainBM)));
        deployed["ChainBalanceManager"] = DeployedContract(address(chainBM), true);

        // Deploy and configure test tokens
        _loadAndConfigureTokens(chainBM);
        
        return address(chainBM);
    }

    function _configureBalanceManagerForCrossChain(address coreBalanceManager, address chainBalanceManager) internal {
        // Get TokenRegistry address from core chain deployment
        address tokenRegistry = _loadTokenRegistryAddress();
        
        if (tokenRegistry == address(0)) {
            return;
        }
        
        // Create a script to run on the core chain
        vm.createSelectFork(CORE_RPC);
        
        // Set TokenRegistry (required for handle() function)
        (bool success,) = coreBalanceManager.call(
            abi.encodeWithSignature("setTokenRegistry(address)", tokenRegistry)
        );
        
        // Register ChainBalanceManager for domain (required for cross-chain messages)
        (success,) = coreBalanceManager.call(
            abi.encodeWithSignature("setChainBalanceManager(uint32,address)", SIDE_DOMAIN, chainBalanceManager)
        );
        
        // Switch back to side chain context for correct deployment file export
        vm.createSelectFork(SIDE_RPC);
    }
    
    function _loadTokenRegistryAddress() internal returns (address) {
        // Try to get core chain name from environment, default to gtx-anvil
        string memory coreChain = vm.envOr("CORE_CHAIN", string("31337"));
        
        // Load core chain deployment file
        string memory root = vm.projectRoot();
        string memory coreDeploymentPath = string.concat(root, "/deployments/", coreChain, ".json");
        
        try vm.readFile(coreDeploymentPath) returns (string memory jsonContent) {
            // Try different possible field names with env var support
            string memory tokenRegistryKey = vm.envOr("TOKEN_REGISTRY_KEY", string("PROXY_TOKENREGISTRY"));
            
            try vm.parseJsonAddress(jsonContent, string.concat(".", tokenRegistryKey)) returns (address tokenRegistry) {
                return tokenRegistry;
            } catch {
                // Fallback to old naming
                try vm.parseJsonAddress(jsonContent, ".TokenRegistry") returns (address tokenRegistry) {
                    return tokenRegistry;
                } catch {
                    return address(0);
                }
            }
        } catch {
            return address(0);
        }
    }

    function _loadAndConfigureTokens(ChainBalanceManager chainBM) internal {
        // Load existing side chain token deployments
        string memory sideChainFile = _getSideChainDeploymentFile();
        string memory jsonContent;
        
        try vm.readFile(sideChainFile) returns (string memory content) {
            jsonContent = content;
        } catch {
            revert(string.concat("Side chain tokens not found at: ", sideChainFile));
        }

        // Parse token addresses from deployment file
        address USDC = vm.parseJsonAddress(jsonContent, ".USDC");
        address WETH = vm.parseJsonAddress(jsonContent, ".WETH");
        address WBTC = vm.parseJsonAddress(jsonContent, ".WBTC");

        // Verify tokens exist by checking if they have code
        require(USDC.code.length > 0, "USDC token not deployed");
        require(WETH.code.length > 0, "WETH token not deployed");
        require(WBTC.code.length > 0, "WBTC token not deployed");

        // Save token addresses to current deployment with deployed mapping
        deployments.push(Deployment("USDC", USDC));
        deployed["USDC"] = DeployedContract(USDC, true);
        
        deployments.push(Deployment("WETH", WETH));
        deployed["WETH"] = DeployedContract(WETH, true);
        
        deployments.push(Deployment("WBTC", WBTC));
        deployed["WBTC"] = DeployedContract(WBTC, true);

        // Whitelist tokens in ChainBalanceManager
        chainBM.addToken(USDC);
        chainBM.addToken(WETH);
        chainBM.addToken(WBTC);
    }

    function _getChainName() internal view returns (string memory) {
        return _getChainName(block.chainid);
    }
    
    function _getChainName(uint256 chainId) internal view returns (string memory) {
        // Map chain IDs to display names
        if (chainId == 31337) return CORE_NAME;      // GTX Core Chain
        if (chainId == 31338) return SIDE_NAME;      // GTX Side Chain  
        if (chainId == 1918988905) return "Rari";
        if (chainId == 4661) return "Appchain";
        if (chainId == 421614) return "Arbitrum Sepolia";
        
        return string.concat("Chain_", vm.toString(chainId));
    }
    
    function _getChainFileName() internal view returns (string memory) {
        return vm.toString(block.chainid);
    }
    

    function _getSideChainDeploymentFile() internal view returns (string memory) {
        string memory sideChain = vm.envOr("SIDE_CHAIN", string("31338"));
        string memory root = vm.projectRoot();
        return string.concat(root, "/deployments/", sideChain, ".json");
    }

    function _deployMockToken(
        string memory symbol,
        string memory name,
        uint8 decimals,
        uint256 initialSupply
    ) internal returns (address) {
        // Deploy a simple mock ERC20 token
        bytes memory bytecode = abi.encodePacked(
            type(MockERC20).creationCode,
            abi.encode(name, symbol, decimals, initialSupply, msg.sender)
        );

        bytes32 saltValue = salt();
        address token;
        assembly {
            token := create2(0, add(bytecode, 0x20), mload(bytecode), saltValue)
        }

        return token;
    }


    function salt() internal view returns (bytes32) {
        return keccak256(abi.encodePacked(block.timestamp, msg.sender));
    }
}

// Simple mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalSupply,
        address _owner
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply;
        balanceOf[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        
        emit Transfer(from, to, value);
        return true;
    }
}