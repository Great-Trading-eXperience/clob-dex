// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

import {GaugeUpgradeable} from "../incentives/gauge/GaugeUpgradeable.sol";
import {GTXMarketMakerVaultStorage} from "./GTXMarketMakerVaultStorage.sol";
import {Currency} from "../libraries/Currency.sol";
import {PoolIdLibrary, PoolKey} from "../libraries/Pool.sol";
import {IOrderBook} from "../interfaces/IOrderBook.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IGTXRouter} from "../interfaces/IGTXRouter.sol";
import {IBalanceManager} from "../interfaces/IBalanceManager.sol";

/**
 * @title GTXMarketMakerVault
 * @notice Market Maker Vault with veTokenomics via Gauge integration
 */
contract GTXMarketMakerVault is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable,
    GaugeUpgradeable,
    GTXMarketMakerVaultStorage
{
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

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

    constructor() {
        _disableInitializers();
    }

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
    ) public initializer {
        __ERC20_init(name, symbol);
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Multicall_init();
        __Gauge_init(_veToken, _gaugeController);

        Storage storage $ = getStorage();
        require(_router != address(0) && _pool != address(0) && _balances != address(0), "Zero address");
        require(_base != address(0) && _quote != address(0), "Zero currency");
        require(_targetRatio <= BASIS_POINTS, "Invalid ratio");
        require(_spread >= _minSpread, "Spread < minSpread");

        $.router = _router;
        $.pool = _pool;
        $.balances = _balances;
        $.baseCurrency = Currency.wrap(_base);
        $.quoteCurrency = Currency.wrap(_quote);

        $.targetRatio = _targetRatio;
        $.spread = _spread;
        $.minSpread = _minSpread;
        $.maxOrderSize = _maxOrderSize;
        $.slippageTolerance = _slippageTolerance;
        $.minActiveOrders = _minActiveOrders;

        $.lastRebalance = block.timestamp;
        $.rebalanceInterval = _rebalanceInterval;

        IERC20(_base).approve(_router, type(uint256).max);
        IERC20(_quote).approve(_router, type(uint256).max);
        IERC20(_base).approve(_balances, type(uint256).max);
        IERC20(_quote).approve(_balances, type(uint256).max);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        GaugeUpgradeable._beforeTokenTransfer(from, to, amount);
    }
    
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        GaugeUpgradeable._afterTokenTransfer(from, to, amount);
    }
    
    function _stakedBalance(address user) internal view override returns (uint256) {
        return balanceOf(user);
    }
    
    function _totalStaked() internal view override returns (uint256) {
        return totalSupply();
    }

    function _getRewardTokens() internal view override returns (address[] memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        return tokens;
    }

    function redeemRewards() external {
        _redeemRewards(msg.sender);
    }

    function getRewardTokens() external view returns (address[] memory) {
        return _getRewardTokens();
    }

    function deposit(uint256 baseAmount, uint256 quoteAmount)
        external
        nonReentrant
        returns (uint256 shares)
    {
        require(baseAmount  > 0 && quoteAmount > 0, "Zero amounts");

        Storage storage $ = getStorage();

        IERC20(Currency.unwrap($.baseCurrency)).safeTransferFrom(msg.sender, address(this), baseAmount);
        IERC20(Currency.unwrap($.quoteCurrency)).safeTransferFrom(msg.sender, address(this), quoteAmount);
        
        IBalanceManager($.balances).deposit($.baseCurrency, baseAmount, address(this), address(this));
        IBalanceManager($.balances).deposit($.quoteCurrency, quoteAmount, address(this), address(this));

        uint256 reserveBase = IBalanceManager($.balances).getBalance(address(this), $.baseCurrency) - baseAmount;
        uint256 reserveQuote = IBalanceManager($.balances).getBalance(address(this), $.quoteCurrency) - quoteAmount;
        uint256 totalShares  = totalSupply();

        uint256 baseDecimals = $.baseCurrency.decimals();
        uint256 quoteDecimals = $.quoteCurrency.decimals();

        uint256 nb = _normalize(baseAmount,  uint8(baseDecimals));
        uint256 nq = _normalize(quoteAmount, uint8(quoteDecimals));
        uint256 rb = _normalize(reserveBase,  uint8(baseDecimals));
        uint256 rq = _normalize(reserveQuote, uint8(quoteDecimals));

        if (totalShares == 0) {
            uint256 root = sqrt(nb * nq);
            require(root > MINIMUM_LIQUIDITY, "Insufficient liquidity");
            shares = root - MINIMUM_LIQUIDITY;
        } else {
            uint256 shareB = (nb * totalShares) / rb;
            uint256 shareQ = (nq * totalShares) / rq;
            shares = shareB < shareQ ? shareB : shareQ;
        }

        require(shares > 0, "Zero shares");
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, baseAmount, quoteAmount, shares);
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _normalize(uint256 amount, uint8 dec)
        internal
        pure
        returns (uint256)
    {
        if (dec < 18) {
            return amount * 10**(18 - dec);
        } else if (dec > 18) {
            return amount / 10**(dec - 18);
        }
        return amount;
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        Storage storage $ = getStorage();
        require(shareAmount > 0 && balanceOf(msg.sender) >= shareAmount, "Invalid shares");

        uint256 totalShares = totalSupply();
        uint256 totalBase = getTotalBaseBalance();
        uint256 totalQuote = getTotalQuoteBalance();

        uint256 basePortion = (totalBase * shareAmount) / totalShares;
        uint256 quotePortion = (totalQuote * shareAmount) / totalShares;

        uint256 availBase = getAvailableBaseBalance();
        uint256 availQuote = getAvailableQuoteBalance();
        if (availBase < basePortion || availQuote < quotePortion) {
            _cancelOrdersToFreeBalance(
                basePortion > availBase ? basePortion - availBase : 0,
                quotePortion > availQuote ? quotePortion - availQuote : 0
            );
        }

        _burn(msg.sender, shareAmount);
        
        IERC20(Currency.unwrap($.baseCurrency)).transfer(msg.sender, basePortion);
        IERC20(Currency.unwrap($.quoteCurrency)).transfer(msg.sender, quotePortion);
        emit Withdraw(msg.sender, basePortion, quotePortion, shareAmount);

        if (shareAmount * 10 > totalShares) _maybeRebalance();
    }
    
    function placeOrder(uint128 price, uint128 quantity, IOrderBook.Side side) external onlyOwner returns (uint48) {
        _validateSpread(price, side);
        
        Storage storage $ = getStorage();
        
        IPoolManager.Pool memory p = _getPool();
        
        uint48 orderId = IGTXRouter($.router).placeOrder(p, price, quantity, side, address(this));
        
        $.activeOrders++;
        
        emit OrderPlaced(orderId, side, price, quantity);
        
        return orderId;
    }
    
    function placeOrderWithDeposit(uint128 price, uint128 quantity, IOrderBook.Side side) external onlyOwner returns (uint48) {
        _validateSpread(price, side);
        
        Storage storage $ = getStorage();
        
        IPoolManager.Pool memory p = _getPool();
        
        uint48 orderId = IGTXRouter($.router).placeOrderWithDeposit(p, price, quantity, side, address(this));
        
        $.activeOrders++;
        
        emit OrderPlaced(orderId, side, price, quantity);
        
        return orderId;
    }
    
    function placeMarketOrder(uint128 quantity, IOrderBook.Side side) external onlyOwner returns (uint48) {
        Storage storage $ = getStorage();
        IPoolManager.Pool memory p = _getPool();
        uint48 orderId = IGTXRouter($.router).placeMarketOrder(p, quantity, side, address(this));
        emit OrderPlaced(orderId, side, 0, quantity);
        return orderId;
    }
    
    function placeMarketOrderWithDeposit(uint128 quantity, IOrderBook.Side side) external onlyOwner returns (uint48) {
        Storage storage $ = getStorage();
        IPoolManager.Pool memory p = _getPool();
        uint48 orderId = IGTXRouter($.router).placeMarketOrderWithDeposit(p, quantity, side, address(this));
        emit OrderPlaced(orderId, side, 0, quantity);
        return orderId;
    }
    
    function cancelOrder(uint48 orderId) external onlyOwner {
        Storage storage $ = getStorage();
        IPoolManager.Pool memory p = _getPool();
        
        IOrderBook.Order memory order = p.orderBook.getOrder(orderId);
        require(order.user == address(this), "Not our order");
        
        IGTXRouter($.router).cancelOrder(p, orderId);
        
        if ($.activeOrders > 0) {
            $.activeOrders--;
        }
        
        emit OrderCancelled(orderId);
    }
    
    function cancelOrdersByPrice(IOrderBook.Side side, uint128 price) external onlyOwner {
        IPoolManager.Pool memory p = _getPool();
        (uint48 orderHead, ) = p.orderBook.getOrderQueue(side, price);
        _cancelOrdersInQueue(p, orderHead);
    }
    
    function rebalance() external {
        Storage storage $ = getStorage();
        if (msg.sender != owner()) {
            require(block.timestamp >= $.lastRebalance + $.rebalanceInterval, "Too soon");
        }
        _rebalance();
    }
    
    function updateParams(
        uint256 _targetRatio,
        uint256 _spread,
        uint256 _minSpread,
        uint256 _maxOrderSize,
        uint256 _slippageTolerance,
        uint256 _minActiveOrders
    ) external onlyOwner {
        Storage storage $ = getStorage();
        require(_targetRatio <= BASIS_POINTS, "Invalid ratio");
        require(_spread >= _minSpread, "Spread < min");
        
        $.targetRatio = _targetRatio;
        $.spread = _spread;
        $.minSpread = _minSpread;
        $.maxOrderSize = _maxOrderSize;
        $.slippageTolerance = _slippageTolerance;
        $.minActiveOrders = _minActiveOrders;
        
        emit ParametersUpdated(
            _targetRatio,
            _spread,
            _minSpread,
            _maxOrderSize,
            _slippageTolerance,
            _minActiveOrders
        );
    }
    
    function setRebalanceInterval(uint256 _interval) external onlyOwner {
        getStorage().rebalanceInterval = _interval;
    }
    
    function getOrder(uint48 orderId) external view returns (IOrderBook.Order memory) {
        IPoolManager.Pool memory p = _getPool();
        return p.orderBook.getOrder(orderId);
    }
    
    function getBestPrice(IOrderBook.Side side) external view returns (IOrderBook.PriceVolume memory) {
        Storage storage $ = getStorage();
        return IGTXRouter($.router).getBestPrice(
            $.baseCurrency,
            $.quoteCurrency,
            side
        );
    }
    
    function getNextBestPrices(IOrderBook.Side side, uint128 price, uint8 count) 
        external view returns (IOrderBook.PriceVolume[] memory) 
    {
        IPoolManager.Pool memory p = _getPool();
        return p.orderBook.getNextBestPrices(side, price, count);
    }
    
    function getAvailableBaseBalance() public view returns (uint256) {
        Storage storage $ = getStorage();
        return IBalanceManager($.balances).getBalance(address(this), $.baseCurrency);
    }
    
    function getAvailableQuoteBalance() public view returns (uint256) {
        Storage storage $ = getStorage();
        return IBalanceManager($.balances).getBalance(address(this), $.quoteCurrency);
    }
    
    function getLockedBaseBalance() public view returns (uint256) {
        Storage storage $ = getStorage();
        IPoolManager.Pool memory p = _getPool();
        return IBalanceManager($.balances).getLockedBalance(
            address(this), 
            address(p.orderBook), 
            $.baseCurrency
        );
    }
    
    function getLockedQuoteBalance() public view returns (uint256) {
        Storage storage $ = getStorage();
        IPoolManager.Pool memory p = _getPool();
        return IBalanceManager($.balances).getLockedBalance(
            address(this), 
            address(p.orderBook), 
            $.quoteCurrency
        );
    }
    
    function getTotalBaseBalance() public view returns (uint256) {
        return getAvailableBaseBalance() + getLockedBaseBalance();
    }
    
    function getTotalQuoteBalance() public view returns (uint256) {
        return getAvailableQuoteBalance() + getLockedQuoteBalance();
    }
    
    function getTotalValue() public view returns (uint256) {
        uint256 baseBalance = getTotalBaseBalance();
        uint256 quoteBalance = getTotalQuoteBalance();
        
        uint128 price = _getCurrentPrice();
        
        uint256 baseValueInQuote = (baseBalance * price) / (10**18);
        
        return baseValueInQuote + quoteBalance;
    }
    
    function _getCurrentPrice() internal view returns (uint128) {
        Storage storage $ = getStorage();
        
        IOrderBook.PriceVolume memory bestBid = IGTXRouter($.router).getBestPrice(
            $.baseCurrency,
            $.quoteCurrency,
            IOrderBook.Side.BUY
        );
        
        IOrderBook.PriceVolume memory bestAsk = IGTXRouter($.router).getBestPrice(
            $.baseCurrency,
            $.quoteCurrency,
            IOrderBook.Side.SELL
        );
        
        if (bestBid.price > 0 && bestAsk.price > 0) {
            return uint128((uint256(bestBid.price) + uint256(bestAsk.price)) / 2);
        } 
        else if (bestBid.price > 0) {
            return bestBid.price;
        } 
        else if (bestAsk.price > 0) {
            return bestAsk.price;
        } 
        else {
            return 2000e6;
        }
    }
    
    function getCurrentPrice() external view returns (uint128) {
        return _getCurrentPrice();
    }

    function _maybeRebalance() internal {
        Storage storage $ = getStorage();
        if (block.timestamp >= $.lastRebalance + $.rebalanceInterval) {
            _rebalance();
        }
    }
    
    function _rebalance() internal {
        _cancelAllOrders();
        
        Storage storage $ = getStorage();
        
        uint256 baseBalance = getAvailableBaseBalance();
        uint256 quoteBalance = getAvailableQuoteBalance();
        uint256 totalBase = baseBalance; 
        uint256 totalQuote = quoteBalance;
        
        uint128 midPrice = _getCurrentPrice();
        
        uint256 quoteInBase = PoolIdLibrary.quoteToBase(totalQuote, midPrice, 18);
        uint256 totalValueInBase = totalBase + quoteInBase;
        
        uint256 targetBase = (totalValueInBase * $.targetRatio) / BASIS_POINTS;
        
        uint128 bidPrice = uint128((uint256(midPrice) * (BASIS_POINTS - $.spread / 2)) / BASIS_POINTS);
        uint128 askPrice = uint128((uint256(midPrice) * (BASIS_POINTS + $.spread / 2)) / BASIS_POINTS);
        
        IPoolManager.Pool memory p = _getPool();
        
        $.activeOrders = 0;
        
        uint256 buyOrders = $.minActiveOrders / 2;
        for (uint256 i = 0; i < buyOrders; i++) {
            uint128 price = uint128(uint256(bidPrice) * (1000 - i * 5) / 1000);
            uint128 size = uint128($.maxOrderSize / buyOrders);
            
            uint256 requiredQuote = PoolIdLibrary.baseToQuote(size, price, 18);
            if (requiredQuote <= quoteBalance) {
                uint48 orderId = IGTXRouter($.router).placeOrder(
                    p,
                    price,
                    size,
                    IOrderBook.Side.BUY,
                    address(this)
                );
                $.activeOrders++;
                emit OrderPlaced(orderId, IOrderBook.Side.BUY, price, size);
                
                quoteBalance -= requiredQuote;
            }
        }
        
        uint256 sellOrders = $.minActiveOrders - buyOrders;
        for (uint256 i = 0; i < sellOrders; i++) {
            uint128 price = uint128(uint256(askPrice) * (1000 + i * 5) / 1000);
            uint128 size = uint128($.maxOrderSize / sellOrders);
            
            if (size <= baseBalance) {
                uint48 orderId = IGTXRouter($.router).placeOrder(
                    p,
                    price,
                    size,
                    IOrderBook.Side.SELL,
                    address(this)
                );
                $.activeOrders++;
                emit OrderPlaced(orderId, IOrderBook.Side.SELL, price, size);
                
                baseBalance -= size;
            }
        }
        
        $.lastRebalance = block.timestamp;
        emit Rebalance(block.timestamp, totalBase, totalQuote);
    }
    
    function _cancelAllOrders() internal {
        IPoolManager.Pool memory p = _getPool();
        Storage storage $ = getStorage();
        
        uint128 midPrice = _getCurrentPrice();
        
        uint128 minPrice = uint128((uint256(midPrice) * 9000) / 10000);
        uint128 maxPrice = uint128((uint256(midPrice) * 11000) / 10000);
        
        for (uint128 price = minPrice; price <= midPrice; price += price / 100) {
            (uint48 orderHead, ) = p.orderBook.getOrderQueue(IOrderBook.Side.BUY, price);
            _cancelOrdersInQueue(p, orderHead);
        }
        
        for (uint128 price = midPrice; price <= maxPrice; price += price / 100) {
            (uint48 orderHead, ) = p.orderBook.getOrderQueue(IOrderBook.Side.SELL, price);
            _cancelOrdersInQueue(p, orderHead);
        }
        
        $.activeOrders = 0;
    }
    
    function _cancelOrdersInQueue(IPoolManager.Pool memory p, uint48 orderHead) internal {
        if (orderHead == 0) return; 
        
        Storage storage $ = getStorage();
        
        IOrderBook.Order memory order = p.orderBook.getOrder(orderHead);
        uint48 currentId = orderHead;
        
        while (currentId != 0) {
            order = p.orderBook.getOrder(currentId);
            uint48 nextId = order.next;
            
            if (order.user == address(this)) {
                try IGTXRouter($.router).cancelOrder(p, currentId) {
                    emit OrderCancelled(currentId);
                } catch {
                }
            }
            
            currentId = nextId;
        }
    }
    
    function _cancelOrdersToFreeBalance(uint256 baseNeeded, uint256 quoteNeeded) internal {
        if (baseNeeded == 0 && quoteNeeded == 0) {
            return;
        }
        
        IPoolManager.Pool memory p = _getPool();
        Storage storage $ = getStorage();
        
        uint256 baseFreed = 0;
        uint256 quoteFreed = 0;
        
        if (baseNeeded > 0) {
            uint128 midPrice = _getCurrentPrice();
            uint128 maxPrice = uint128((uint256(midPrice) * 11000) / 10000);
            
            for (uint128 price = midPrice; price <= maxPrice && baseFreed < baseNeeded; price += price / 100) {
                (uint48 orderHead, ) = p.orderBook.getOrderQueue(IOrderBook.Side.SELL, price);
                baseFreed += _cancelOrdersUntilFree(p, orderHead, baseNeeded - baseFreed, true);
            }
        }
        
        if (quoteNeeded > 0) {
            uint128 midPrice = _getCurrentPrice();
            uint128 minPrice = uint128((uint256(midPrice) * 9000) / 10000);
            
            for (uint128 price = midPrice; price >= minPrice && quoteFreed < quoteNeeded; price -= price / 100) {
                (uint48 orderHead, ) = p.orderBook.getOrderQueue(IOrderBook.Side.BUY, price);
                quoteFreed += _cancelOrdersUntilFree(p, orderHead, quoteNeeded - quoteFreed, false);
            }
        }
        
        uint256 availableBase = getAvailableBaseBalance();
        uint256 availableQuote = getAvailableQuoteBalance();
        
        require(
            availableBase >= baseNeeded && availableQuote >= quoteNeeded, 
            "Failed to free balance"
        );
    }
    
    function _cancelOrdersUntilFree(
        IPoolManager.Pool memory p, 
        uint48 orderHead, 
        uint256 amountNeeded,
        bool isBase
    ) internal returns (uint256 amountFreed) {
        if (orderHead == 0) return 0; 
        
        Storage storage $ = getStorage();
        
        IOrderBook.Order memory order = p.orderBook.getOrder(orderHead);
        uint48 currentId = orderHead;
        amountFreed = 0;
        
        while (currentId != 0 && amountFreed < amountNeeded) {
            order = p.orderBook.getOrder(currentId);
            uint48 nextId = order.next; 
            
            if (order.user == address(this)) {
                uint256 amount;
                
                if (isBase) {
                    if (order.side == IOrderBook.Side.SELL) {
                        amount = order.quantity - order.filled;
                    }
                } else {
                    if (order.side == IOrderBook.Side.BUY) {
                        amount = PoolIdLibrary.baseToQuote(order.quantity - order.filled, order.price, 18);
                    }
                }
                
                if (amount > 0) {
                    try IGTXRouter($.router).cancelOrder(p, currentId) {
                        amountFreed += amount;
                        
                        // Update counter
                        if ($.activeOrders > 0) {
                            $.activeOrders--;
                        }
                        
                        emit OrderCancelled(currentId);
                    } catch {

                    }
                }
            }
            
            currentId = nextId;
        }
        
        return amountFreed;
    }
    
    function _getPool() internal view returns (IPoolManager.Pool memory) {
        Storage storage $ = getStorage();
        PoolKey memory key = IPoolManager($.pool).createPoolKey($.baseCurrency, $.quoteCurrency);
        return IPoolManager($.pool).getPool(key);
    }
    
    function _validateSpread(uint128 price, IOrderBook.Side side) public view {
        Storage storage $ = getStorage();
        
        IOrderBook.PriceVolume memory bestPrice = IGTXRouter($.router).getBestPrice(
            $.baseCurrency,
            $.quoteCurrency,
            side == IOrderBook.Side.BUY ? IOrderBook.Side.SELL : IOrderBook.Side.BUY
        );
        
        if (bestPrice.price == 0) {
            return;
        }
        
        if (side == IOrderBook.Side.BUY) {
            if (price >= bestPrice.price) {
                revert("Price crosses the spread");
            }
        } else {
            if (price <= bestPrice.price) {
                revert("Price crosses the spread");
            }
        }
        
        uint256 actualSpread;
        if (side == IOrderBook.Side.BUY) {
            actualSpread = ((bestPrice.price - price) * BASIS_POINTS) / bestPrice.price;
        } else {
            actualSpread = ((price - bestPrice.price) * BASIS_POINTS) / price;
        }
        
        require(actualSpread >= $.minSpread, "Spread too narrow");
    }
    
    function validateSpread(uint128 price, IOrderBook.Side side) external view returns (bool) {
        try GTXMarketMakerVault(address(this))._validateSpread(price, side) {
            return true;
        } catch {
            return false;
        }
    }
}