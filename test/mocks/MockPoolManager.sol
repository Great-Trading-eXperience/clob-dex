// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MockERC6909Lock.sol";
import "../../src/PoolManager.sol";
// import "../../src/interfaces/IPoolManager.sol";

/// @notice MockPoolManager inherits PoolManager and provides mock implementations for testing
contract MockPoolManager is MockERC6909Lock {
    constructor(address _owner) {}

    function calculateAmountAndCurrency(
        PoolKey calldata, /*key*/
        Price, /*price*/
        Quantity, /*quantity*/
        Side /*side*/
    ) external pure returns (Currency currency, uint256 amount) {
        return (Currency.wrap(address(0)), 0);
    }
}
