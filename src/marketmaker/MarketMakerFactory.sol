// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {MarketMaker} from "./MarketMaker.sol";

contract MarketMakerFactory {
    mapping(address => bool) public marketMakers;

    function createMarketMaker(
        address
    ) external {
        address marketMaker = address(new MarketMaker("name", "symbol", address(1), address(1)));
        marketMakers[marketMaker] = true;
    }

    function isValidMarketMaker(
        address _marketMaker
    ) external view returns (bool) {
        return marketMakers[_marketMaker];
    }
}
