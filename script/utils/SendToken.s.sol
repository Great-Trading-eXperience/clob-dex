// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../src/mocks/MockToken.sol";
import "../../src/mocks/MockUSDC.sol";
import "../../src/mocks/MockWETH.sol";
import "./DeployHelpers.s.sol";
import "forge-std/console.sol";

contract SendToken is DeployHelpers {
    // Contract address keys
    string constant WETH_ADDRESS = "MOCK_TOKEN_WETH";
    string constant USDC_ADDRESS = "MOCK_TOKEN_USDC";
    string constant WBTC_ADDRESS = "MOCK_TOKEN_WBTC";

    // Mock tokens
    MockUSDC mockUSDC;
    MockWETH mockWETH;
    MockToken mockWBTC;

    // Token transfer parameters
    address public recipient;
    uint256 public amount;
    string public tokenType;

    function run() public {
        uint256 deployerPrivateKey = getDeployerKey();
        address deployer = vm.addr(deployerPrivateKey);

        loadDeployments();
        loadMockTokens();

        // Get parameters from environment or set defaults for demo
        recipient = vm.envOr("RECIPIENT_ADDRESS", address(0x1234567890123456789012345678901234567890));
        amount = vm.envOr("SEND_AMOUNT", uint256(1000 * 1e6)); // Default 1000 USDC
        tokenType = vm.envOr("TOKEN_TYPE", string("USDC")); // Default to USDC

        console.log("\n=== Token Mint Configuration ===");
        console.log("Deployer:", deployer);
        console.log("Recipient:", recipient);
        console.log("Token Type:", tokenType);
        console.log("Mint Amount:", amount);

        vm.startBroadcast(deployerPrivateKey);

        if (keccak256(abi.encodePacked(tokenType)) == keccak256(abi.encodePacked("USDC"))) {
            sendUSDC(deployer, recipient, amount);
        } else if (keccak256(abi.encodePacked(tokenType)) == keccak256(abi.encodePacked("WETH"))) {
            sendWETH(deployer, recipient, amount);
        } else if (keccak256(abi.encodePacked(tokenType)) == keccak256(abi.encodePacked("WBTC"))) {
            sendWBTC(deployer, recipient, amount);
        } else if (keccak256(abi.encodePacked(tokenType)) == keccak256(abi.encodePacked("ETH"))) {
            sendETH(deployer, recipient, amount);
        } else {
            revert("Unsupported token type. Use USDC, WETH, WBTC, or ETH");
        }

        vm.stopBroadcast();
    }

    function sendUSDC(address sender, address to, uint256 mintAmount) private {
        console.log("\n=== USDC Mint ===");
        console.log("USDC Contract:", address(mockUSDC));
        console.log("Recipient:", to);
        
        // Log balance before mint
        uint256 recipientBalanceBefore = mockUSDC.balanceOf(to);
        
        console.log("Recipient balance before:", recipientBalanceBefore);
        console.log("Mint amount:", mintAmount);
        
        // Perform mint
        mockUSDC.mint(to, mintAmount);
        
        // Log balance after mint
        uint256 recipientBalanceAfter = mockUSDC.balanceOf(to);
        
        console.log("Recipient balance after:", recipientBalanceAfter);
        console.log("Mint completed successfully!");
        
        // Verify mint
        require(recipientBalanceAfter == recipientBalanceBefore + mintAmount, "Recipient balance verification failed");
    }

    function sendWETH(address sender, address to, uint256 mintAmount) private {
        console.log("\n=== WETH Mint ===");
        console.log("WETH Contract:", address(mockWETH));
        console.log("Recipient:", to);
        
        // Log balance before mint
        uint256 recipientBalanceBefore = mockWETH.balanceOf(to);
        
        console.log("Recipient balance before:", recipientBalanceBefore);
        console.log("Mint amount:", mintAmount);
        
        // Perform mint
        mockWETH.mint(to, mintAmount);
        
        // Log balance after mint
        uint256 recipientBalanceAfter = mockWETH.balanceOf(to);
        
        console.log("Recipient balance after:", recipientBalanceAfter);
        console.log("Mint completed successfully!");
        
        // Verify mint
        require(recipientBalanceAfter == recipientBalanceBefore + mintAmount, "Recipient balance verification failed");
    }

    function sendWBTC(address sender, address to, uint256 mintAmount) private {
        console.log("\n=== WBTC Mint ===");
        console.log("WBTC Contract:", address(mockWBTC));
        console.log("Recipient:", to);
        
        // Log balance before mint
        uint256 recipientBalanceBefore = mockWBTC.balanceOf(to);
        
        console.log("Recipient balance before:", recipientBalanceBefore);
        console.log("Mint amount:", mintAmount);
        
        // Perform mint
        mockWBTC.mint(to, mintAmount);
        
        // Log balance after mint
        uint256 recipientBalanceAfter = mockWBTC.balanceOf(to);
        
        console.log("Recipient balance after:", recipientBalanceAfter);
        console.log("Mint completed successfully!");
        
        // Verify mint
        require(recipientBalanceAfter == recipientBalanceBefore + mintAmount, "Recipient balance verification failed");
    }

    function sendETH(address sender, address to, uint256 transferAmount) private {
        console.log("\n=== ETH Transfer ===");
        console.log("Recipient:", to);
        
        // Log balance before transfer
        uint256 senderBalanceBefore = sender.balance;
        uint256 recipientBalanceBefore = to.balance;
        
        console.log("Sender balance before:", senderBalanceBefore);
        console.log("Recipient balance before:", recipientBalanceBefore);
        console.log("Transfer amount:", transferAmount);
        
        // Check if sender has enough balance
        require(senderBalanceBefore >= transferAmount, "Insufficient ETH balance");
        
        // Perform transfer
        payable(to).transfer(transferAmount);
        
        // Log balance after transfer
        uint256 senderBalanceAfter = sender.balance;
        uint256 recipientBalanceAfter = to.balance;
        
        console.log("Sender balance after:", senderBalanceAfter);
        console.log("Recipient balance after:", recipientBalanceAfter);
        console.log("Transfer completed successfully!");
        
        // Verify transfer
        require(senderBalanceAfter == senderBalanceBefore - transferAmount, "Sender balance verification failed");
        require(recipientBalanceAfter == recipientBalanceBefore + transferAmount, "Recipient balance verification failed");
    }

    function loadMockTokens() private {
        console.log("\n=== Loading Mock Tokens ===");

        address wethAddr = deployed[WETH_ADDRESS].addr;
        address usdcAddr = deployed[USDC_ADDRESS].addr;
        address wbtcAddr = deployed[WBTC_ADDRESS].addr;

        require(wethAddr != address(0), "WETH address not found in deployments");
        require(usdcAddr != address(0), "USDC address not found in deployments");
        require(wbtcAddr != address(0), "WBTC address not found in deployments");

        mockWETH = MockWETH(wethAddr);
        mockUSDC = MockUSDC(usdcAddr);
        mockWBTC = MockToken(wbtcAddr);

        console.log("Loaded MockWETH:", address(mockWETH));
        console.log("Loaded MockUSDC:", address(mockUSDC));
        console.log("Loaded MockWBTC:", address(mockWBTC));
    }
}