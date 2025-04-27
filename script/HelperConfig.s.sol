// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import {MockToken} from "../src/mocks/MockToken.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockWETH} from "../src/mocks/MockWETH.sol";
import {DeployHelpers} from "./DeployHelpers.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is DeployHelpers {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address usdc;
        address weth;
        address wbtc;
        address link;
        address pepe;
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
            usdc: 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F, // MockUSDC
            weth: 0xb2e9Eabb827b78e2aC66bE17327603778D117d18, // MockWETH
            wbtc: 0xc2CC2835219A55a27c5184EaAcD9b8fCceF00F85, // MockWBTC
            link: 0x24b1ca69816247Ef9666277714FADA8B1F2D901E, // MockChainlink
            pepe: 0x7FB2a815Fa88c2096960999EC8371BccDF147874 // MockPEPE
        });
    }

    function getArbitrumSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x6AcaCCDacE944619678054Fe0eA03502ed557651,
            weth: 0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E,
            wbtc: address(0), // Placeholder
            link: address(0), // Placeholder
            pepe: address(0) // Placeholder
        });
    }

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtc: address(0), // Placeholder
            link: address(0), // Placeholder
            pepe: address(0) // Placeholder
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        // check if there is an existing config
        if (activeNetworkConfig.usdc != address(0)) {
            return activeNetworkConfig;
        }
        uint256 deployerPrivateKey = getDeployerKey();
        vm.startBroadcast(deployerPrivateKey);

        MockToken usdc = new MockToken("Mock USDC", "USDC", 6);
        MockToken weth = new MockToken("Mock WETH", "WETH", 18);
        MockToken wbtc = new MockToken("Mock WBTC", "WBTC", 8);
        MockToken pepe = new MockToken("Mock PEPE", "PEPE", 18);
        MockToken chainlink = new MockToken("Mock Chainlink", "LINK", 18);

        vm.stopBroadcast();

        return NetworkConfig({
            usdc: address(usdc),
            weth: address(weth),
            wbtc: address(wbtc),
            link: address(chainlink),
            pepe: address(pepe)
        });
    }
}
