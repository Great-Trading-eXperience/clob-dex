//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import {VotingEscrowMainchain} from "../src/incentives/votingescrow/VotingEscrowMainchain.sol";
import {VotingControllerUpg} from "../src/incentives/voting-controller/VotingControllerUpg.sol";
import {GaugeControllerMainchainUpg} from
    "../src/incentives/gauge-controller/GaugeControllerMainchainUpg.sol";
import {MarketMakerFactory} from "../src/marketmaker/MarketMakerFactory.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployGauge is Script {
    uint256 deployerPrivateKey;
    address owner;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // mock token
        MockToken token = new MockToken("Test Token", "TEST", 18);

        // voting escrow
        VotingEscrowMainchain votingEscrow =
            new VotingEscrowMainchain(address(token), address(0), 1e6);

        // voting controller
        address votingControllerImp =
            address(new VotingControllerUpg(address(votingEscrow), address(0)));
        VotingControllerUpg votingController = VotingControllerUpg(
            address(
                new TransparentUpgradeableProxy(
                    votingControllerImp,
                    address(this),
                    abi.encodeWithSelector(VotingControllerUpg.initialize.selector, 100_000)
                )
            )
        );

        // market maker factory
        MarketMakerFactory marketMakerFactory =
            new MarketMakerFactory(address(votingEscrow), address(0));

        // gauge controller
        address gaugeControllerImp = address(
            new GaugeControllerMainchainUpg(
                address(votingController), address(token), address(marketMakerFactory)
            )
        );
        GaugeControllerMainchainUpg gaugeController = GaugeControllerMainchainUpg(
            address(
                new TransparentUpgradeableProxy(
                    gaugeControllerImp,
                    address(this),
                    abi.encodeWithSelector(GaugeControllerMainchainUpg.initialize.selector)
                )
            )
        );

        // setup market maker factory
        marketMakerFactory.setVeToken(address(votingEscrow));
        marketMakerFactory.setGaugeController(address(gaugeController));

        vm.stopBroadcast();

        console.log("VotingEscrowMainchain deployed at", address(votingEscrow));
        console.log("VotingControllerUpg deployed at", address(votingController));
        console.log("MarketMakerFactory deployed at", address(marketMakerFactory));
        console.log("GaugeControllerMainchainUpg deployed at", address(gaugeController));
    }
}
