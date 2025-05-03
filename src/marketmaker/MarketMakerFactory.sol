// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {MarketMaker} from "./MarketMaker.sol";

contract MarketMakerFactory {
    mapping(address => bool) public marketMakers;

    address public veToken;
    address public gaugeController;

    constructor(address _veToken, address _gaugeController) {
        veToken = _veToken;
        gaugeController = _gaugeController;
    }

    function createMarketMaker(
        string memory name,
        string memory symbol
    ) external returns (address) {
        address marketMaker = address(new MarketMaker(name, symbol, veToken, gaugeController));
        marketMakers[marketMaker] = true;
        return marketMaker;
    }

    function isValidMarketMaker(
        address _marketMaker
    ) external view returns (bool) {
        return marketMakers[_marketMaker];
    }

    function setVeToken(
        address _veToken
    ) external {
        veToken = _veToken;
    }

    function setGaugeController(
        address _gaugeController
    ) external {
        gaugeController = _gaugeController;
    }
}
