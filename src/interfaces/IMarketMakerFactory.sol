// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IMarketMakerFactory {
    function isValidMarketMaker(
        address _marketMaker
    ) external view returns (bool);
}
