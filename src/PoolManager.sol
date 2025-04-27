// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";
import {OrderBook} from "./OrderBook.sol";

import {IBalanceManager} from "./interfaces/IBalanceManager.sol";
import {IOrderBook} from "./interfaces/IOrderBook.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {Currency} from "./libraries/Currency.sol";
import {PoolId, PoolKey} from "./libraries/Pool.sol";
import {PoolManagerStorage} from "./storages/PoolManagerStorage.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract PoolManager is Initializable, OwnableUpgradeable, PoolManagerStorage, IPoolManager {
    function initialize(address _owner, address _balanceManager, address _orderBookBeacon) public initializer {
        __Ownable_init(_owner);
        Storage storage $ = getStorage();
        $.balanceManager = _balanceManager;
        $.orderBookBeacon = _orderBookBeacon;
    }

    function getPool(
        PoolKey calldata key
    ) external view returns (Pool memory) {
        return getStorage().pools[key.toId()];
    }

    function getPoolId(
        PoolKey calldata key
    ) external pure returns (PoolId) {
        return key.toId();
    }

    function setRouter(
        address _router
    ) external onlyOwner {
        if (_router == address(0)) {
            revert InvalidRouter();
        }
        Storage storage $ = getStorage();
        IBalanceManager($.balanceManager).setAuthorizedOperator(_router, true);
        $.router = _router;
    }

    function createPool(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.TradingRules memory _tradingRules
    ) external returns (PoolId) {
        Storage storage $ = getStorage();
        if ($.router == address(0)) {
            revert InvalidRouter();
        }

        PoolKey memory key = createPoolKey(_baseCurrency, _quoteCurrency);
        PoolId id = key.toId();

        address orderBookProxy = Upgrades.deployBeaconProxy(
            $.orderBookBeacon,
            abi.encodeCall(OrderBook.initialize, (address(this), $.balanceManager, _tradingRules, key))
        );

        IOrderBook orderBookInterface = IOrderBook(orderBookProxy);

        IPoolManager.Pool memory pool = Pool({
            orderBook: IOrderBook(orderBookProxy),
            baseCurrency: key.baseCurrency,
            quoteCurrency: key.quoteCurrency
        });

        $.pools[id] = pool;

        $.pools[id] =
            Pool({orderBook: orderBookInterface, baseCurrency: key.baseCurrency, quoteCurrency: key.quoteCurrency});

        if (!$.registeredCurrencies[key.baseCurrency]) {
            $.registeredCurrencies[key.baseCurrency] = true;
            $.allCurrencies.push(key.baseCurrency);
            emit CurrencyAdded(key.baseCurrency);
        }

        if (!$.registeredCurrencies[key.quoteCurrency]) {
            $.registeredCurrencies[key.quoteCurrency] = true;
            $.allCurrencies.push(key.quoteCurrency);
            emit CurrencyAdded(key.quoteCurrency);
        }

        $.poolLiquidity[id] = 1;

        orderBookInterface.setRouter($.router);
        IBalanceManager($.balanceManager).setAuthorizedOperator(address(orderBookProxy), true);

        emit PoolCreated(id, address(orderBookProxy), key.baseCurrency, key.quoteCurrency);

        return id;
    }

    function addCommonIntermediary(
        Currency currency
    ) external onlyOwner {
        Storage storage $ = getStorage();
        require(!$.isCommonIntermediary[currency], "Already a common intermediary");

        $.commonIntermediaries.push(currency);
        $.isCommonIntermediary[currency] = true;

        emit IntermediaryAdded(currency);
    }

    function removeCommonIntermediary(
        Currency currency
    ) external onlyOwner {
        Storage storage $ = getStorage();
        require($.isCommonIntermediary[currency], "Not a common intermediary");

        uint256 length = $.commonIntermediaries.length;
        for (uint256 i = 0; i < length; i++) {
            if (Currency.unwrap($.commonIntermediaries[i]) == Currency.unwrap(currency)) {
                $.commonIntermediaries[i] = $.commonIntermediaries[length - 1];
                $.commonIntermediaries.pop();
                break;
            }
        }

        $.isCommonIntermediary[currency] = false;

        emit IntermediaryRemoved(currency);
    }

    function updatePoolLiquidity(PoolKey calldata key, uint256 liquidityScore) external {
        Storage storage $ = getStorage();
        require(msg.sender == owner() || msg.sender == $.router, "Not authorized");

        PoolId id = key.toId();
        require(address($.pools[id].orderBook) != address(0), "Pool does not exist");

        $.poolLiquidity[id] = liquidityScore;

        emit PoolLiquidityUpdated(id, liquidityScore);
    }

    function getAllCurrencies() external view returns (Currency[] memory) {
        return getStorage().allCurrencies;
    }

    function getCommonIntermediaries() external view returns (Currency[] memory) {
        return getStorage().commonIntermediaries;
    }

    function poolExists(Currency currency1, Currency currency2) public view returns (bool) {
        PoolKey memory key = createPoolKey(currency1, currency2);
        return address(getStorage().pools[key.toId()].orderBook) != address(0);
    }

    function getPoolLiquidityScore(Currency currency1, Currency currency2) external view returns (uint256) {
        PoolKey memory key = createPoolKey(currency1, currency2);
        return getStorage().poolLiquidity[key.toId()];
    }

    function createPoolKey(Currency currency1, Currency currency2) public pure returns (PoolKey memory) {
        return PoolKey({baseCurrency: currency1, quoteCurrency: currency2});
    }
}
