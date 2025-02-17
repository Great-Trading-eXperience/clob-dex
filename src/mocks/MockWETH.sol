// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockWETH - A mock contract for WETH token
/// @notice This contract is used for testing purposes to simulate WETH token behavior
contract MockWETH is ERC20 {
    constructor() ERC20("MockWETH", "MWETH") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}
