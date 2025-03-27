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
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract PoolManager is Ownable, IPoolManager {
    address private balanceManager;
    address private router;

    mapping(PoolId => Pool) public pools;

    constructor(address _owner, address _balanceManager) Ownable(_owner) {
        balanceManager = _balanceManager;
    }

    function getPool(PoolKey calldata key) external view returns (Pool memory) {
        return pools[key.toId()];
    }

    function getPoolId(PoolKey calldata key) external pure returns (PoolId) {
        return key.toId();
    }

    function setRouter(address _router) external onlyOwner {
        if (_router == address(0)) {
            revert InvalidRouter();
        }
        IBalanceManager(balanceManager).setAuthorizedOperator(_router, true);
        router = _router;
    }

    function createPool(
        PoolKey calldata key,
        address baseVault,
        address quoteVault,
        uint256 _lotSize,
        uint256 _maxOrderAmount
    ) external returns (address) {
        if (router == address(0)) {
            revert InvalidRouter();
        }

        if (baseVault != address(0)) {
            if (ERC4626(baseVault).asset() != Currency.unwrap(key.baseCurrency)) {
                revert InvalidBaseVault(key, baseVault);
            }
        }

        if (quoteVault != address(0)) {
            if (ERC4626(quoteVault).asset() != Currency.unwrap(key.quoteCurrency)) {
                revert InvalidQuoteVault(key, quoteVault);
            }
        }

        PoolId id = key.toId();
        OrderBook orderBook = new OrderBook(
            address(this),
            balanceManager,
            _maxOrderAmount,
            _lotSize,
            key,
            baseVault,
            quoteVault
        );

        // Effects: Update the state before any external interaction
        pools[id] = Pool({
            orderBook: orderBook,
            baseCurrency: key.baseCurrency,
            quoteCurrency: key.quoteCurrency,
            lotSize: _lotSize,
            maxOrderAmount: _maxOrderAmount,
            baseVault: baseVault,
            quoteVault: quoteVault
        });

        // Interactions: External calls after state changes
        orderBook.setRouter(router);
        IBalanceManager(balanceManager).setAuthorizedOperator(
            address(orderBook),
            true
        );

        emit PoolCreated(
            id,
            address(orderBook),
            key.baseCurrency,
            key.quoteCurrency,
            baseVault,
            quoteVault,
            _lotSize,
            _maxOrderAmount
        );

        return address(orderBook);
    }
}
