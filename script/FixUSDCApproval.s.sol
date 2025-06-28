// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

contract FixUSDCApproval is Script {
    // Addresses from Rise network (chain ID 11155931)
    address constant BALANCE_MANAGER = 0xd3168EBb535cDFff693af02045c39BfdE230813D;
    address constant USDC_TOKEN = 0x4b9A14Ca8b00b6D83c8D663a4D9471A79CA6f58e;
    
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address userAddress = vm.addr(privateKey);
        
        console.log("=== FIXING USDC APPROVAL ===");
        console.log("Chain ID:", block.chainid);
        console.log("User Address:", userAddress);
        console.log("USDC Token:", USDC_TOKEN);
        console.log("BalanceManager:", BALANCE_MANAGER);
        
        vm.startBroadcast(privateKey);
        
        // Approve maximum amount for USDC
        (bool success, ) = USDC_TOKEN.call(
            abi.encodeWithSignature(
                "approve(address,uint256)", 
                BALANCE_MANAGER, 
                type(uint256).max
            )
        );
        
        require(success, "USDC approval failed");
        
        console.log("USDC approval successful!");
        
        vm.stopBroadcast();
        
        // Verify the approval
        (bool checkSuccess, bytes memory allowanceData) = USDC_TOKEN.staticcall(
            abi.encodeWithSignature("allowance(address,address)", userAddress, BALANCE_MANAGER)
        );
        
        if (checkSuccess) {
            uint256 allowance = abi.decode(allowanceData, (uint256));
            console.log("New USDC Allowance:", allowance);
            console.log("Required amount: 950000000");
            console.log("Sufficient allowance:", allowance >= 950000000);
        }
    }
}