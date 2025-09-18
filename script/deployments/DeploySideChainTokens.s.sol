// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../utils/DeployHelpers.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DeploySideChainTokens
 * @dev Deploy tokens on side chain for cross-chain testing
 * This script only deploys the tokens, not the ChainBalanceManager
 */
contract DeploySideChainTokens is DeployHelpers {
    
    function run() external {
        uint256 deployerPrivateKey = getDeployerKey();
        
        console.log("========== DEPLOYING SIDE CHAIN TOKENS ==========");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Configure token supplies with reasonable defaults
        uint256 usdtSupply = vm.envOr("USDC_SUPPLY", uint256(1000000 * 10**6)); // 1M USDC
        uint256 wethSupply = vm.envOr("WETH_SUPPLY", uint256(1000 * 10**18)); // 1000 WETH
        uint256 wbtcSupply = vm.envOr("WBTC_SUPPLY", uint256(100 * 10**8)); // 100 WBTC
        
        // Deploy side chain tokens
        address USDC = _deployMockToken("USDC", "Tether USD", 6, usdtSupply);
        address WETH = _deployMockToken("WETH", "Wrapped Ether", 18, wethSupply);
        address WBTC = _deployMockToken("WBTC", "Wrapped Bitcoin", 8, wbtcSupply);
        
        console.log("USDC=%s", USDC);
        console.log("WETH=%s", WETH);
        console.log("WBTC=%s", WBTC);
        
        vm.stopBroadcast();
        
        // Save deployments to JSON file
        deployments.push(Deployment("USDC", USDC));
        deployed["USDC"] = DeployedContract(USDC, true);
        
        deployments.push(Deployment("WETH", WETH));
        deployed["WETH"] = DeployedContract(WETH, true);
        
        deployments.push(Deployment("WBTC", WBTC));
        deployed["WBTC"] = DeployedContract(WBTC, true);
        
        exportDeployments();
        
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Deployment addresses saved to JSON file:");
        console.log("USDC=%s", USDC);
        console.log("WETH=%s", WETH);
        console.log("WBTC=%s", WBTC);
    }
    
    /**
     * @dev Deploy a mock ERC20 token
     */
    function _deployMockToken(
        string memory symbol,
        string memory name,
        uint8 decimals,
        uint256 initialSupply
    ) internal returns (address) {
        MockERC20 token = new MockERC20(name, symbol, decimals, initialSupply);
        
        return address(token);
    }
    
}

/**
 * @title MockERC20
 * @dev Simple mock ERC20 token for testing
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}