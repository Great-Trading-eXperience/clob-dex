// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../../src/vaults/VaultFactory.sol";
import {GTXVault} from "../../src/vaults/GTXVault.sol";

/**
 * @title DeployWBTCVault
 * @notice Deploy GTX Vault for WBTC on Base Sepolia
 */
contract DeployWBTCVault is Script {
    address constant VAULT_FACTORY = 0x72774445e92788c986157B798e085D77262A95B7;
    address constant WBTC = 0x0a6756095519627Bdd389e8ce5a64f658fdc0cD2; // MockWBTC

    function run() public returns (address vault) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n========== DEPLOYING WBTC VAULT ==========");
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 84532, "Must be Base Sepolia (84532)");

        console.log("Deployer:", deployer);
        console.log("VaultFactory:", VAULT_FACTORY);
        console.log("WBTC:", WBTC);

        vm.startBroadcast(deployerPrivateKey);

        VaultFactory factory = VaultFactory(VAULT_FACTORY);

        vault = factory.deploySimpleVault(
            WBTC,
            "GTX WBTC Yield Vault",
            "gtxWBTC"
        );

        console.log("gtxWBTC Vault deployed at:", vault);

        vm.stopBroadcast();

        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("VAULT_gtxWBTC_BASE_SEPOLIA=%s", vault);
        console.log("Asset: WBTC");
        console.log("Owner:", GTXVault(vault).owner());

        return vault;
    }
}
