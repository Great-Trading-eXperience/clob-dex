// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OrderId, Quantity, Side} from "./types/Types.sol";
import {Currency} from "./types/Currency.sol";
import {PoolKey, PoolId} from "./types/Pool.sol";
import {Price} from "./libraries/BokkyPooBahsRedBlackTreeLibrary.sol";
import {OrderBook} from "./OrderBook.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {ERC6909Lock} from "./ERC6909Lock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import {BalanceManager} from "./BalanceManager.sol";

contract PoolManager is IPoolManager, ERC6909Lock {
    address public owner;

    mapping(PoolId => Pool) public pools;

    constructor(address initialOwner) {
        owner = initialOwner;
        // balanceManager = IBalanceManager(_balanceManager);
    }

    function initializePool(PoolKey calldata key, uint256 _lotSize, uint256 _feePercentage) external {
        PoolId id = key.toId();
        IOrderBook orderBook = new OrderBook(address(this), key);
        pools[id] = Pool({
            orderBook: orderBook,
            baseCurrency: key.baseCurrency,
            quoteCurrency: key.quoteCurrency,
            lotSize: _lotSize,
            feePercentage: _feePercentage
        });
        emit PoolInitialized(id, address(orderBook), key.baseCurrency, key.quoteCurrency, _lotSize);
    }

    function getPool(PoolId id) external view override returns (Pool memory) {
        return pools[id];
    }

    function getPoolId(PoolKey calldata key) external pure returns (PoolId) {
        return key.toId();
    }

    function deposit(Currency currency, uint256 amount) public {
        _deposit(currency, amount);
    }

    function _deposit(Currency currency, uint256 amount) private {
        IERC20(Currency.unwrap(currency)).transferFrom(msg.sender, address(this), amount);
        if (!isOperator[msg.sender][address(this)]) {
            setOperator(address(this), true);
        }
        _mint(msg.sender, currency.toId(), amount);
    }

    function withdraw(Currency currency, uint256 amount) external {
        _burn(msg.sender, currency.toId(), amount);
        currency.transfer(msg.sender, amount);
    }

    function placeOrder(PoolKey calldata key, Price price, Quantity quantity, Side side)
        public
        returns (OrderId orderId)
    {
        Pool storage pool = pools[key.toId()];
        if (!isOperator[msg.sender][address(pool.orderBook)]) {
            setOperator(address(pool.orderBook), true);
        }
        orderId = pool.orderBook.placeOrder(price, quantity, side, msg.sender);
    }

    function placeOrderWhileDeposit(PoolKey calldata key, Price price, Quantity quantity, Side side)
        external
        returns (OrderId orderId)
    {
        (Currency currency, uint256 amount) = _calculateAmountAndCurrency(key, price, quantity, side);
        _deposit(currency, amount);
        orderId = placeOrder(key, price, quantity, side);
    }

    function calculateAmountAndCurrency(PoolKey calldata key, Price price, Quantity quantity, Side side)
        external
        view
        returns (Currency currency, uint256 amount)
    {
        return _calculateAmountAndCurrency(key, price, quantity, side);
    }

    function _calculateAmountAndCurrency(PoolKey calldata key, Price price, Quantity quantity, Side side)
        internal
        view
        returns (Currency currency, uint256 amount)
    {
        uint8 baseCurrencyDecimals = key.baseCurrency.decimals();
        uint8 quoteCurrencyDecimals = key.quoteCurrency.decimals();
        uint8 priceDecimals = price.decimals();
        currency = (side == Side.BUY) ? key.quoteCurrency : key.baseCurrency;

        if (side == Side.BUY) {
            amount = (Quantity.unwrap(quantity) * Price.unwrap(price)) / (10 ** priceDecimals);
            amount = (amount * 10 ** quoteCurrencyDecimals) / 10 ** baseCurrencyDecimals;
        } else {
            amount = Quantity.unwrap(quantity);
        }
    }
}
