
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "../../src/faucet/Faucet.sol";
import "../utils/DeployHelpers.s.sol";
import {console} from "forge-std/console.sol";

contract SetupFaucet is DeployHelpers {
    // Contract address keys
    string constant FAUCET_ADDRESS = "PROXY_FAUCET";

    Faucet public faucet;

    function setUp() public {
        loadDeployments();

        // Load deployed contract address
        address faucetProxy = deployed[FAUCET_ADDRESS].addr;
        faucet = Faucet(payable(faucetProxy));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Log current configuration
        uint256 faucetAmount = faucet.getFaucetAmount();
        uint256 faucetCooldown = faucet.getCooldown();
        
        console.log("Previous Faucet Amount:", faucetAmount);
        console.log("Previous Faucet Cooldown:", faucetCooldown);
        
        // Update configuration
        faucet.updateFaucetAmount(1e12);
        faucet.updateFaucetCooldown(1);
        
        // Log updated configuration
        faucetAmount = faucet.getFaucetAmount();
        faucetCooldown = faucet.getCooldown();
        console.log("Current Faucet Amount:", faucetAmount);
        console.log("Current Faucet Cooldown:", faucetCooldown);

        vm.stopBroadcast();
    }
}