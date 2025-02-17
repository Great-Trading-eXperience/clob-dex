// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey, PoolId} from "../types/Pool.sol";
import {Currency} from "../types/Currency.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {Price} from "../libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderId, Quantity, Side} from "../types/Types.sol";

// import {IBalanceManager} from "./IBalanceManager.sol";
// import {IERC6909Lock} from "../interfaces/external/IERC6909Lock.sol";
// import {IPoolManager} from "../interfaces/IPoolManager.sol";

interface IPoolManager {
    struct Pool {
        uint256 lotSize;
        Currency baseCurrency;
        Currency quoteCurrency;
        IOrderBook orderBook;
        uint256 feePercentage;
    }

    event PoolInitialized(
        PoolId indexed id, address indexed orderBook, Currency baseCurrency, Currency quoteCurrency, uint256 lotSize
    );

    function initializePool(PoolKey calldata key, uint256 _lotSize, uint256 _feePercentage) external;

    function getPool(PoolId id) external view returns (Pool memory);

    function getPoolId(PoolKey calldata key) external pure returns (PoolId);

    function deposit(Currency currency, uint256 amount) external;

    function withdraw(Currency currency, uint256 amount) external;

    function placeOrder(PoolKey calldata key, Price price, Quantity quantity, Side side) external returns (OrderId);

    function placeOrderWhileDeposit(PoolKey calldata key, Price price, Quantity quantity, Side side)
        external
        returns (OrderId);

    function calculateAmountAndCurrency(PoolKey calldata key, Price price, Quantity quantity, Side side)
        external
        view
        returns (Currency currency, uint256 amount);
}
