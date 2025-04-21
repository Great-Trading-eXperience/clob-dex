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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Upgrades} from "../lib/openzeppelin-foundry-upgrades/src/Upgrades.sol";


contract PoolManager is Initializable, OwnableUpgradeable, IPoolManager {
    address private balanceManager;
    address private router;
    address private orderBookBeacon;

    mapping(PoolId => Pool) public pools;

    // Track all currencies that have at least one pool
    mapping(Currency => bool) public registeredCurrencies;
    Currency[] public allCurrencies;

    // Common intermediaries (prioritized for routing)
    Currency[] public commonIntermediaries;
    mapping(Currency => bool) public isCommonIntermediary;

    // Liquidity ranking for path finding (higher is better)
    mapping(PoolId => uint256) public poolLiquidity;

    event CurrencyAdded(Currency currency);
    event IntermediaryAdded(Currency currency);
    event IntermediaryRemoved(Currency currency);
    event PoolLiquidityUpdated(PoolId poolId, uint256 newLiquidity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner, address _balanceManager, address _orderBookBeacon) public initializer {
        __Ownable_init(_owner);
        balanceManager = _balanceManager;
        orderBookBeacon = _orderBookBeacon;
    }

    function getPool(
        PoolKey calldata key
    ) external view returns (Pool memory) {
        return pools[key.toId()];
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
        IBalanceManager(balanceManager).setAuthorizedOperator(_router, true);
        router = _router;
    }

    function createPool(
        Currency _baseCurrency,
        Currency _quoteCurrency,
        IOrderBook.TradingRules memory _tradingRules
    ) external returns (PoolId) {
        if (router == address(0)) {
            revert InvalidRouter();
        }

        PoolKey memory key = createPoolKey(_baseCurrency, _quoteCurrency);
        PoolId id = key.toId();

        address orderBookProxy = Upgrades.deployBeaconProxy(
            orderBookBeacon,
            abi.encodeCall(OrderBook.initialize, (address(this), balanceManager, _tradingRules, key))
        );

        IOrderBook orderBookInterface = IOrderBook(orderBookProxy);

        // Effects: Update the state before any external interaction
        pools[id] = Pool({
            orderBook: orderBookInterface,
            baseCurrency: key.baseCurrency,
            quoteCurrency: key.quoteCurrency
        });

        // Register currencies if they're new
        if (!registeredCurrencies[key.baseCurrency]) {
            registeredCurrencies[key.baseCurrency] = true;
            allCurrencies.push(key.baseCurrency);
            emit CurrencyAdded(key.baseCurrency);
        }

        if (!registeredCurrencies[key.quoteCurrency]) {
            registeredCurrencies[key.quoteCurrency] = true;
            allCurrencies.push(key.quoteCurrency);
            emit CurrencyAdded(key.quoteCurrency);
        }

        // Set initial pool liquidity to 1 (minimum value)
        poolLiquidity[id] = 1;

        // Interactions: External calls after state changes
        orderBookInterface.setRouter(router);
        IBalanceManager(balanceManager).setAuthorizedOperator(address(orderBookProxy), true);

        emit PoolCreated(id, address(orderBookProxy), key.baseCurrency, key.quoteCurrency);

        return id;
    }

    /**
     * @notice Adds a currency to the list of common intermediaries (preferred for routing)
     * @param currency The currency to add
     */
    function addCommonIntermediary(
        Currency currency
    ) external onlyOwner {
        require(!isCommonIntermediary[currency], "Already a common intermediary");

        commonIntermediaries.push(currency);
        isCommonIntermediary[currency] = true;

        emit IntermediaryAdded(currency);
    }

    /**
     * @notice Removes a currency from the list of common intermediaries
     * @param currency The currency to remove
     */
    function removeCommonIntermediary(
        Currency currency
    ) external onlyOwner {
        require(isCommonIntermediary[currency], "Not a common intermediary");

        // Find and remove from the array
        uint256 length = commonIntermediaries.length;
        for (uint256 i = 0; i < length; i++) {
            if (Currency.unwrap(commonIntermediaries[i]) == Currency.unwrap(currency)) {
                // Replace with the last element and pop
                commonIntermediaries[i] = commonIntermediaries[length - 1];
                commonIntermediaries.pop();
                break;
            }
        }

        isCommonIntermediary[currency] = false;

        emit IntermediaryRemoved(currency);
    }

    /**
     * @notice Updates the liquidity score for a pool (affects routing priority)
     * @param key The pool key
     * @param liquidityScore The new liquidity score (higher means more priority in routing)
     */
    function updatePoolLiquidity(PoolKey calldata key, uint256 liquidityScore) external {
        // In a production system, this would be restricted to authorized updaters
        // or calculated automatically based on volume/depth
        require(msg.sender == owner() || msg.sender == router, "Not authorized");

        PoolId id = key.toId();
        require(address(pools[id].orderBook) != address(0), "Pool does not exist");

        poolLiquidity[id] = liquidityScore;

        emit PoolLiquidityUpdated(id, liquidityScore);
    }

    /**
     * @notice Get all registered currencies that have at least one pool
     * @return currencies Array of all currencies in the system
     */
    function getAllCurrencies() external view returns (Currency[] memory) {
        return allCurrencies;
    }

    /**
     * @notice Get common intermediary currencies (preferred for routing)
     * @return intermediaries Array of common intermediary currencies
     */
    function getCommonIntermediaries() external view returns (Currency[] memory) {
        return commonIntermediaries;
    }

    /**
     * @notice Check if a pool exists between two currencies
     * @param currency1 First currency
     * @param currency2 Second currency
     * @return exists Whether a pool exists
     */
    function poolExists(Currency currency1, Currency currency2) public view returns (bool) {
        PoolKey memory key = createPoolKey(currency1, currency2);
        return address(pools[key.toId()].orderBook) != address(0);
    }

    /**
     * @notice Get the liquidity score for a pool
     * @param currency1 First currency
     * @param currency2 Second currency
     * @return score The liquidity score (0 if pool doesn't exist)
     */
    function getPoolLiquidityScore(
        Currency currency1,
        Currency currency2
    ) external view returns (uint256) {
        PoolKey memory key = createPoolKey(currency1, currency2);
        return poolLiquidity[key.toId()];
    }

    /**
     * @notice Create a pool key with the correct order of currencies
     */
    function createPoolKey(
        Currency currency1,
        Currency currency2
    ) public pure returns (PoolKey memory) {
        return PoolKey({baseCurrency: currency1, quoteCurrency: currency2});
    }
}
