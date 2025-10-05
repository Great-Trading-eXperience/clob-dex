# GTX Trading System - Data Population Guide

Quickly populate the trading system with test data using two different trader accounts.

## Quick Setup

### 1. Prerequisites
```bash
# Ensure deployment is complete
make validate-deployment

# Set trader accounts
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export PRIVATE_KEY_2=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
```

### 2. Complete Trading Flow
```bash
# Step 1: Primary trader deposits tokens
PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=1000000000 make test-local-deposit network=gtx_core_devnet
PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=10000000000000000000 make test-local-deposit network=gtx_core_devnet

# Step 2: Transfer tokens to secondary trader
make transfer-tokens network=gtx_core_devnet recipient=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 token=USDC amount=5000000000
make transfer-tokens network=gtx_core_devnet recipient=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 token=WETH amount=5000000000000000000

# Step 3: Secondary trader deposits tokens  
PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=2000000000 TEST_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 make test-local-deposit network=gtx_core_devnet
PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=2000000000000000000 TEST_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 make test-local-deposit network=gtx_core_devnet

# Step 4: Primary trader creates liquidity
PRIVATE_KEY=$PRIVATE_KEY make fill-orderbook network=gtx_core_devnet

# Step 5: Secondary trader executes trades
PRIVATE_KEY=$PRIVATE_KEY_2 make market-order network=gtx_core_devnet
```

## Common Issues

**Market Order MemoryOOG Error**:
- **Cause**: Same address used for both limit and market orders
- **Solution**: Always use PRIVATE_KEY_2 for market orders
- **Alternative**: If market orders fail, use `PRIVATE_KEY=$PRIVATE_KEY_2 make fill-orderbook network=gtx_core_devnet`

**"Insufficient balance" errors**: 
- Ensure token transfers completed before secondary trader deposits
- Verify secondary trader has deposits in BalanceManager (not just token wallet)
- Use `TEST_RECIPIENT` parameter to deposit to correct address
- Run: `make diagnose-market-order network=gtx_core_devnet` to debug issues

**Market Order "Insufficient gsWETH balance" Error**:
- **Cause**: Secondary trader deposits went to wrong address in BalanceManager
- **Solution**: Use `TEST_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8` in deposit commands
- **Check**: Verify balance with `cast call $BALANCE_MANAGER "getBalance(address,address)" $SECONDARY_TRADER $TOKEN --rpc-url https://core-devnet.gtxdex.xyz`

## Validation

```bash
# Validate data population was successful
make validate-data-population

# This checks:
# ✅ Both traders have synthetic token balances  
# ✅ OrderBook has liquidity (limit orders placed)
# ✅ Trading events emitted (market orders executed)
```

## Expected Results

After successful data population, you should see:

### Trading Activity
- **Market order executed**: Secondary trader sells ~0.001 ETH for ~1881 USDC
- **Order ID**: 19 (or similar)
- **Transaction hash**: Available in logs
- **Block**: Recent block number

### Indexer Data
The indexer at `http://localhost:42070` should now show populated trades:

```graphql
query MyQuery {
  tradess {
    items {
      timestamp
      quantity
      price
      poolId
      orderId
      id
      chainId
      transactionId
    }
  }
}
```

Should return trade data instead of empty `{ "data": { "tradess": { "items": [] } } }`

### Balance Changes
- **Primary trader**: Created 20 limit orders (10 buy + 10 sell)
- **Secondary trader**: Executed market sell, received USDC for ETH

## Quick Verification

```bash
# Check deployment is working
make validate-deployment

# Verify trader addresses are different  
echo "Primary: $(cast wallet address --private-key $PRIVATE_KEY)"
echo "Secondary: $(cast wallet address --private-key $PRIVATE_KEY_2)"
```

---

**⏱️ Total time**: ~3-5 minutes  
**✅ Result**: Two traders with active trading positions in the system