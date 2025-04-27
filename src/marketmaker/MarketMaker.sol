// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Gauge} from "../incentives/gauge/Gauge.sol";

contract MarketMaker is ERC20, Gauge {
    constructor(
        string memory name,
        string memory symbol,
        address _veToken,
        address _gaugeController
    ) ERC20(name, symbol) Gauge(_veToken, _gaugeController) {}

    function deposit(
        uint256 amount
    ) external {
        _mint(msg.sender, amount);
    }

    function withdraw(
        uint256 amount
    ) external {
        _burn(msg.sender, amount);
    }

    function redeemRewards() external {
        _redeemRewards(msg.sender);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return _getRewardTokens();
    }

    function _stakedBalance(
        address user
    ) internal view override returns (uint256) {
        return balanceOf(user);
    }

    function _totalStaked() internal view override returns (uint256) {
        return totalSupply();
    }

    function _update(address from, address to, uint256 amount) internal override {
        Gauge._beforeTokenTransfer(from, to, amount);
        Gauge._afterTokenTransfer(from, to, amount);
    }
}
