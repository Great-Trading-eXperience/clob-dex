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
        _beforeTokenTransfer(address(0), msg.sender, amount);
        _mint(msg.sender, amount);
        _afterTokenTransfer(address(0), msg.sender, amount);
    }

    function withdraw(
        uint256 amount
    ) external {
        _beforeTokenTransfer(msg.sender, address(0), amount);
        _burn(msg.sender, amount);
        _afterTokenTransfer(msg.sender, address(0), amount);
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

    // solhint-disable-next-line ordering
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        Gauge._beforeTokenTransfer(from, to, amount);
    }

    // solhint-disable-next-line ordering
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        Gauge._afterTokenTransfer(from, to, amount);
    }

    function _getRewardTokens() internal view override returns (address[] memory) {
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = token;
        return rewardTokens;
    }
}
