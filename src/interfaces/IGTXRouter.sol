// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OrderId, Quantity, Side} from "../types/Types.sol";
import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/Pool.sol";
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";

interface IGTXRouter {
    function placeOrder(
        PoolKey calldata key,
        Price price,
        Quantity quantity,
        Side side
    ) external returns (OrderId orderId);

    function placeOrderWithDeposit(
        PoolKey calldata key,
        Price price,
        Quantity quantity,
        Side side
    ) external returns (OrderId orderId);

    function placeMarketOrder(
        PoolKey calldata key,
        Quantity quantity,
        Side side
    ) external returns (OrderId orderId);

    function placeMarketOrderWithDeposit(
        PoolKey calldata key,
        Price price,
        Quantity quantity,
        Side side
    ) external returns (OrderId orderId);

    function cancelOrder(PoolKey calldata key, Side side, Price price, OrderId orderId) external;
}
