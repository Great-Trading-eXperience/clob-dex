# CLOB Trading Architecture Documentation

## Overview

The Cross-Chain CLOB (Central Limit Order Book) trading system consists of several interconnected components that work together to provide trading functionality for synthetic tokens on Rari testnet.

## Component Architecture

### 1. OrderBook Beacon Pattern

**OrderBook Beacon: `0xa8630B75d92814b79dE1C5A170d00Ef0714b3C28`**

- **Shared by ALL trading pools** - This is a single beacon that manages the implementation for all OrderBook contracts
- **Purpose**: Provides upgradeable pattern for all OrderBook instances
- **Usage**: When a new pool is created, PoolManager deploys a BeaconProxy pointing to this beacon
- **Upgrade**: Updating the beacon updates ALL OrderBook contracts simultaneously

```solidity
// In PoolManager.createPool():
BeaconProxy orderBookProxy = new BeaconProxy($.orderBookBeacon, initData);
// Each pool gets its own OrderBook proxy, but they share the same beacon/implementation
```

### 2. Component Relationships

```
┌─────────────────────────────────────────────────────────┐
│                    Trading Flow                         │
└─────────────────────────────────────────────────────────┘

User Request
     ↓
[Router] ────────→ [PoolManager] ────────→ [OrderBook (Pool 1)]
     ↓                   ↓                        ↓
     ↓                   ↓                        ↓
     ↓                   ↓              [OrderBook (Pool 2)]
     ↓                   ↓                        ↓
     ↓                   ↓              [OrderBook (Pool N)]
     ↓                   ↓                        ↓
[BalanceManager] ←──────┴────────────────────────┘
     ↓
[Synthetic Tokens: gsUSDT, gsWETH, gsWBTC]
```

### 3. Current Deployment Status on Rari

| Component | Address | Owner | Status |
|-----------|---------|--------|--------|
| **BalanceManager** | `0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5` | `0x77C037fbF42e85dB1487B390b08f58C00f438812` | ✅ Deployed |
| **PoolManager** | `0xF38489749c3e65c82a9273c498A8c6614c34754b` | `0x77C037fbF42e85dB1487B390b08f58C00f438812` | ⚠️  Deployed, router not set |
| **Router** | `0xcf3953cA780e2BC08e9B8aAB30f801F6883108ba` | `0x77C037fbF42e85dB1487B390b08f58C00f438812` | ✅ Deployed |
| **OrderBook Beacon** | `0xa8630B75d92814b79dE1C5A170d00Ef0714b3C28` | N/A (Beacon) | ✅ Deployed |

### 4. Component Responsibilities

#### Router (`GTXRouter`)
- **Entry Point**: All user trading requests go through the Router
- **Functions**: 
  - `placeLimitOrder()` - Place limit orders
  - `placeMarketOrder()` - Execute market orders  
  - `cancelOrder()` - Cancel existing orders
- **Authorization**: Authorized operator in BalanceManager
- **Relationship**: Calls PoolManager to find the correct pool, then calls OrderBook

#### PoolManager
- **Pool Factory**: Creates and manages trading pools
- **Functions**:
  - `createPool()` - Creates new trading pairs (e.g., gsWETH/gsUSDT)
  - `getPool()` - Retrieves pool information
- **Beacon Usage**: Uses OrderBook beacon to create OrderBook proxies for each pool
- **Authorization**: Must have router set before creating pools

#### OrderBook (Per Pool)
- **Order Management**: Maintains buy/sell order queues for specific trading pair
- **Functions**:
  - `placeOrder()` - Add orders to the book
  - `matchOrder()` - Execute trades between orders
  - `getBestPrice()` - Get current best bid/ask
- **Instance**: Each trading pool has its own OrderBook contract (proxy)
- **Shared Implementation**: All OrderBooks use the same beacon implementation

#### BalanceManager
- **Token Management**: Manages synthetic token balances
- **Functions**:
  - `lock()` - Lock tokens when placing orders
  - `unlock()` - Unlock tokens when canceling orders
  - `transferFrom()` - Execute token transfers during trades
- **Authorization**: Must authorize Router and PoolManager as operators

### 5. Current Configuration Issues

❌ **Router Not Set in PoolManager**
```bash
# This failed due to ownership:
poolManager.setRouter(routerProxy)
# Error: OwnableUnauthorizedAccount
```

❌ **No Trading Pools Created**
- Need to create gsWETH/gsUSDT pool
- Need to create gsWBTC/gsUSDT pool

### 6. Required Configuration Steps

1. **Set Router in PoolManager**
   ```solidity
   poolManager.setRouter(0xcf3953cA780e2BC08e9B8aAB30f801F6883108ba);
   ```

2. **Create Trading Pools**
   ```solidity
   // gsWETH/gsUSDT (1 WETH = X USDT)
   poolManager.createPool(
       Currency.wrap(gsWETH), 
       Currency.wrap(gsUSDT), 
       tradingRules
   );
   
   // gsWBTC/gsUSDT (1 WBTC = X USDT)  
   poolManager.createPool(
       Currency.wrap(gsWBTC), 
       Currency.wrap(gsUSDT), 
       tradingRules
   );
   ```

3. **Verify Authorizations**
   ```solidity
   // BalanceManager should have these operators:
   balanceManager.isAuthorizedOperator(poolManager) // should be true
   balanceManager.isAuthorizedOperator(router) // should be true
   ```

### 7. Trading Flow Example

**Example: User places limit order to buy 1 WETH at 4000 USDT**

1. **User calls Router**: `router.placeLimitOrder(pool, price=4000, quantity=1, side=BUY)`

2. **Router finds Pool**: Router gets pool info from PoolManager for gsWETH/gsUSDT

3. **Router calls OrderBook**: `orderBook.placeOrder(price, quantity, side, user)`

4. **OrderBook locks collateral**: 
   - Calls `balanceManager.lock(user, gsUSDT, 4000)` (lock USDT for buying)
   
5. **OrderBook adds to queue**: Order added to buy-side order queue at price 4000

6. **Matching (if applicable)**: If there's a sell order at ≤4000, trade executes:
   - `balanceManager.transferFrom()` - Transfer tokens between users
   - `balanceManager.unlock()` - Unlock unused collateral

### 8. Ownership Summary

**Current Ownership**: All components owned by `0x77C037fbF42e85dB1487B390b08f58C00f438812`
- ✅ BalanceManager owner: `0x77C037fbF42e85dB1487B390b08f58C00f438812` 
- ✅ PoolManager owner: `0x77C037fbF42e85dB1487B390b08f58C00f438812`
- ✅ Router owner: `0x77C037fbF42e85dB1487B390b08f58C00f438812`

This means the private key `0x0967cf3226ff3b10c198740a6002e61b8879d6e72f54d315d190d7e7bf5b9857` can configure all components.

### 9. Next Steps

1. Run configuration script to set router in PoolManager
2. Create gsWETH/gsUSDT and gsWBTC/gsUSDT trading pools  
3. Test end-to-end trading flow
4. Verify all authorizations are correct

### 10. Security Considerations

- **Single Point of Control**: All contracts owned by same address - consider multi-sig for production
- **Operator Permissions**: BalanceManager has authorized operators (Router, PoolManager) that can move funds
- **Upgrade Risk**: OrderBook beacon can upgrade all OrderBooks simultaneously - requires careful testing