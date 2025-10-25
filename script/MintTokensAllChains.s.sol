// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IERC20Mintable {
    function mint(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract MintTokensAllChains is Script {
    // Large amounts to mint (in base units)
    uint256 constant USDT_MINT_AMOUNT = 1000000 * 10 ** 6; // 1M USDT
    uint256 constant WETH_MINT_AMOUNT = 1000 * 10 ** 18; // 1K WETH
    uint256 constant WBTC_MINT_AMOUNT = 100 * 10 ** 8; // 100 WBTC

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Multi-Chain Token Minting ===");
        console.log("Deployer address:", deployer);
        console.log("Chain ID:", block.chainid);
        
        // Determine which chain we're on and mint appropriate tokens
        if (block.chainid == 4661) {
            console.log("Network: Appchain Testnet");
            mintAppchainTokens(deployerPrivateKey, deployer);
        } else if (block.chainid == 11155931) {
            console.log("Network: Rise Sepolia");
            mintRiseTokens(deployerPrivateKey, deployer);
        } else if (block.chainid == 421614) {
            console.log("Network: Arbitrum Sepolia");
            mintArbitrumTokens(deployerPrivateKey, deployer);
        } else {
            console.log("ERROR: Unsupported chain ID:", block.chainid);
            return;
        }
        
        console.log("=== Minting Complete ===");
    }
    
    function mintAppchainTokens(uint256 privateKey, address recipient) internal {
        vm.startBroadcast(privateKey);
        
        console.log("--- Appchain Token Addresses ---");
        address USDT = 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516;
        address WETH = 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F;
        address WBTC = 0xb2e9Eabb827b78e2aC66bE17327603778D117d18;
        
        console.log("USDT:", USDT);
        console.log("WETH:", WETH);
        console.log("WBTC:", WBTC);
        console.log("");
        
        mintToken(USDT, recipient, USDT_MINT_AMOUNT, "USDT");
        mintToken(WETH, recipient, WETH_MINT_AMOUNT, "WETH");
        mintToken(WBTC, recipient, WBTC_MINT_AMOUNT, "WBTC");
        
        vm.stopBroadcast();
    }
    
    function mintRiseTokens(uint256 privateKey, address recipient) internal {
        vm.startBroadcast(privateKey);
        
        console.log("--- Rise Sepolia Token Addresses ---");
        address USDT = 0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6;
        address WETH = 0x567a076BEEF17758952B05B1BC639E6cDd1A31EC;
        address WBTC = 0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E;
        
        console.log("USDT:", USDT);
        console.log("WETH:", WETH);
        console.log("WBTC:", WBTC);
        console.log("");
        
        mintToken(USDT, recipient, USDT_MINT_AMOUNT, "USDT");
        mintToken(WETH, recipient, WETH_MINT_AMOUNT, "WETH");
        mintToken(WBTC, recipient, WBTC_MINT_AMOUNT, "WBTC");
        
        vm.stopBroadcast();
    }
    
    function mintArbitrumTokens(uint256 privateKey, address recipient) internal {
        vm.startBroadcast(privateKey);
        
        console.log("--- Arbitrum Sepolia Token Addresses ---");
        address USDT = 0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a;
        address WETH = 0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7;
        address WBTC = 0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A;
        
        console.log("USDT:", USDT);
        console.log("WETH:", WETH);
        console.log("WBTC:", WBTC);
        console.log("");
        
        mintToken(USDT, recipient, USDT_MINT_AMOUNT, "USDT");
        mintToken(WETH, recipient, WETH_MINT_AMOUNT, "WETH");
        mintToken(WBTC, recipient, WBTC_MINT_AMOUNT, "WBTC");
        
        vm.stopBroadcast();
    }
    
    function mintToken(address tokenAddress, address recipient, uint256 amount, string memory tokenName) internal {
        console.log("=== Minting", tokenName, "===");
        
        IERC20Mintable token = IERC20Mintable(tokenAddress);
        
        // Check balance before
        uint256 balanceBefore = token.balanceOf(recipient);
        uint8 decimals = token.decimals();
        console.log("Balance before:", balanceBefore);
        console.log("Decimals:", decimals);
        console.log("Amount to mint (raw):", amount);
        console.log("Amount to mint (readable):", amount / (10 ** decimals), tokenName);
        
        // Mint tokens
        console.log("Minting tokens...");
        token.mint(recipient, amount);
        
        // Check balance after
        uint256 balanceAfter = token.balanceOf(recipient);
        uint256 minted = balanceAfter - balanceBefore;
        console.log("Balance after:", balanceAfter);
        console.log("Actually minted:", minted);
        console.log("SUCCESS: Minted", minted / (10 ** decimals), tokenName);
        console.log("");
    }
}