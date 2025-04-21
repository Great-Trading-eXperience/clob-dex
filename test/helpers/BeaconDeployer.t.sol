// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

contract BeaconDeployer {
    function deployUpgradeableContract(
        address implementation,
        address beaconOwner,
        bytes memory initializeData
    ) public returns (BeaconProxy proxy, address beaconAddress) {
        IBeacon beacon = new UpgradeableBeacon(implementation, beaconOwner);
        address beaconAddress = address(beacon);

        BeaconProxy proxy = new BeaconProxy(
            beaconAddress,
            initializeData
        );

        return (proxy, beaconAddress);
    }
}