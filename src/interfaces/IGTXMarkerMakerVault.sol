// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IOrderBook} from "../interfaces/IOrderBook.sol";

/**
 * @title IGTXMarketMakerVault
 * @notice Interface for GTX Market Maker Vault with veTokenomics via Gauge integration
 */
interface IGTXMarketMakerVault {
    event Deposit(address indexed user, uint256 baseAmount, uint256 quoteAmount, uint256 shares);
    event Withdraw(address indexed user, uint256 baseAmount, uint256 quoteAmount, uint256 shares);
    event OrderPlaced(uint48 orderId, IOrderBook.Side side, uint128 price, uint128 quantity);
    event OrderCancelled(uint48 orderId);
    event Rebalance(uint256 timestamp, uint256 baseBalance, uint256 quoteBalance);
    event FeesReceived(uint256 amount, address token);
    event ParametersUpdated(
        uint256 targetRatio,
        uint256 spread,
        uint256 minSpread,
        uint256 maxOrderSize,
        uint256 slippageTolerance,
        uint256 minActiveOrders
    );

    function initialize(
        string memory name,
        string memory symbol,
        address _veToken,
        address _gaugeController,
        address _router,
        address _pool,
        address _balances,
        address _base,
        address _quote,
        uint256 _targetRatio,
        uint256 _spread,
        uint256 _minSpread,
        uint256 _maxOrderSize,
        uint256 _slippageTolerance,
        uint256 _minActiveOrders,
        uint256 _rebalanceInterval,
        address _owner
    ) external;

    function redeemRewards() external;

    function getRewardTokens() external view returns (address[] memory);

    function deposit(uint256 baseAmount, uint256 quoteAmount)
        external
        returns (uint256 shares);

    function withdraw(uint256 shareAmount) external;
    
    function placeOrder(uint128 price, uint128 quantity, IOrderBook.Side side) external returns (uint48);
    
    function placeMarketOrder(uint128 quantity, IOrderBook.Side side) external returns (uint48);
    
    function cancelOrder(uint48 orderId) external;
    
    function cancelOrdersByPrice(IOrderBook.Side side, uint128 price) external;
    
    function rebalance() external;
    
    function updateParams(
        uint256 _targetRatio,
        uint256 _spread,
        uint256 _minSpread,
        uint256 _maxOrderSize,
        uint256 _slippageTolerance,
        uint256 _minActiveOrders
    ) external;
    
    function setRebalanceInterval(uint256 _interval) external;
    
    function getOrder(uint48 orderId) external view returns (IOrderBook.Order memory);
    
    function getBestPrice(IOrderBook.Side side) external view returns (IOrderBook.PriceVolume memory);
    
    function getNextBestPrices(IOrderBook.Side side, uint128 price, uint8 count) 
        external view returns (IOrderBook.PriceVolume[] memory);
    
    function getAvailableBaseBalance() external view returns (uint256);
    
    function getAvailableQuoteBalance() external view returns (uint256);
    
    function getLockedBaseBalance() external view returns (uint256);
    
    function getLockedQuoteBalance() external view returns (uint256);
    
    function getTotalBaseBalance() external view returns (uint256);
    
    function getTotalQuoteBalance() external view returns (uint256);
    
    function getTotalValue() external view returns (uint256);
    
    function getCurrentPrice() external view returns (uint128);

    function validateSpread(uint128 price, IOrderBook.Side side) external view returns (bool);

    function targetRatio() external view returns (uint256);

    function spread() external view returns (uint256);

    function minSpread() external view returns (uint256);

    function maxOrderSize() external view returns (uint256);

    function slippageTolerance() external view returns (uint256);

    function minActiveOrders() external view returns (uint256);
}