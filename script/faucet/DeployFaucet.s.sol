// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "../DeployHelpers.s.sol";
import "../../src/faucet/Faucet.sol";

contract DeployFaucet is DeployHelpers {
    function run() public {
        loadDeployments();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconOwner = getDeployedAddress("OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy beacon
        console.log("========== DEPLOYING FAUCET BEACON ==========");
        address faucetBeacon = Upgrades.deployBeacon("Faucet.sol", beaconOwner);

        // Store beacon address
        deployments.push(Deployment("BEACON_FAUCET", faucetBeacon));
        deployed["BEACON_FAUCET"] = DeployedContract(faucetBeacon, true);

        // Deploy proxy
        console.log("\n========== DEPLOYING FAUCET PROXY ==========");
        address faucetProxy = Upgrades.deployBeaconProxy(
            faucetBeacon,
            abi.encodeCall(Faucet.initialize, (beaconOwner))
        );

        // Store proxy address
        deployments.push(Deployment("PROXY_FAUCET", faucetProxy));
        deployed["PROXY_FAUCET"] = DeployedContract(faucetProxy, true);

        console.log("PROXY_FAUCET=%s", faucetProxy);

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("# Deployment addresses saved to JSON file:");
        console.log("BEACON_FAUCET=%s", faucetBeacon);
        console.log("PROXY_FAUCET=%s", faucetProxy);

        vm.stopBroadcast();

        // Export deployments to JSON file
        exportDeployments();
    }

    // Helper function to get deployed addresses from mapping or fallback to env var
    function getDeployedAddress(
        string memory key
    ) private view returns (address) {
        // Check if address exists in deployments
        if (deployed[key].isSet) {
            return deployed[key].addr;
        }

        // Fall back to env var
        return vm.envOr(key, address(0));
    }
}
