// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
/// @title MockUSDC - A mock contract for USDC token
/// @notice This contract is used for testing purposes to simulate USDC token behavior

contract MockUSDC is ERC20 {
    constructor() ERC20("MockUSDC", "MUSDC") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
