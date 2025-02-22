// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";

contract HelperConfig is DeployHelpers {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address usdc;
        address weth;
    }

    constructor() {
        if (block.chainid == 1) {
            activeNetworkConfig = getEthMainnetConfig();
        } else if (block.chainid == 421_614) {
            activeNetworkConfig = getArbitrumSepoliaConfig();
        } else if (block.chainid == 11_155_931) {
            activeNetworkConfig = getRiseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getRiseSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x2E6D0aA9ca3348870c7cbbC28BF6ea90A3C1fE36,
            weth: 0xc4CebF58836707611439e23996f4FA4165Ea6A28
        });
    }

    function getArbitrumSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x6AcaCCDacE944619678054Fe0eA03502ed557651,
            weth: 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E
        });
    }

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        // check if there is an existing config
        if (activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast(getDeployerKey());

        MockUSDC mockUSDC = new MockUSDC();
        MockWETH mockWeth = new MockWETH();

        vm.stopBroadcast();

        return NetworkConfig({weth: address(mockWeth), usdc: address(mockUSDC)});
    }
}
