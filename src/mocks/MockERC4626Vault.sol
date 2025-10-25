// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockERC4626Vault
 * @dev Simple ERC-4626 vault for testing yield functionality
 * Simulates yield generation by allowing owner to add yield tokens
 */
contract MockERC4626Vault is ERC4626 {
    address public vaultOwner;

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        vaultOwner = msg.sender;
    }

    /**
     * @dev Simulate yield generation by depositing additional underlying tokens
     * This increases the assets-per-share ratio
     */
    function addYield(uint256 amount) external {
        require(msg.sender == vaultOwner, "Only owner can add yield");
        IERC20(asset()).transferFrom(msg.sender, address(this), amount);
        // Yield is automatically reflected in totalAssets()
    }

    /**
     * @dev Get total yield generated (total assets - total shares)
     */
    function getTotalYield() external view returns (uint256) {
        uint256 total = totalAssets();
        uint256 shares = totalSupply();

        if (shares == 0) return 0;

        // Yield is the difference between total assets and shares at 1:1
        return total > shares ? total - shares : 0;
    }
}
