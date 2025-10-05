# Trading Bot Testing - Quick Start Guide

## 🎯 Goal
Test that trading bots can place orders and trades are recorded in the indexer.

## ⚡ Prerequisites (5 minutes)

Before starting, ensure these are running:

```bash
# 1. Anvil blockchain
anvil --chain-id 31337 --port 8545

# 2. Contracts deployed
cd /Users/renaka/gtx/clob-dex && ./deploy.sh

# 3. PostgreSQL for indexer
# (should already be running on port 5433)
```

## 🚀 Quick Start (10 minutes)

### Step 1: Start Indexer
```bash
cd /Users/renaka/gtx/clob-indexer

# Auto-configure with latest deployment addresses
BALANCE_MANAGER=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.BalanceManager.address')
POOL_MANAGER=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.PoolManager.address')
USDC_ADDRESS=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.USDC.address')
WETH_ADDRESS=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.WETH.address')

# Update indexer config
cat > .env.core-chain << EOF
PONDER_DATABASE_URL=postgresql://postgres:password@localhost:5433/ponder_core
PONDER_PORT=42070
CHAIN_ID=31337
PONDER_RPC_URL=https://core-devnet.gtxdex.xyz

BALANCEMANAGER_CONTRACT_GTX_CORE_DEVNET_ADDRESS=$BALANCE_MANAGER
POOLMANAGER_CONTRACT_GTX_CORE_DEVNET_ADDRESS=$POOL_MANAGER
USDC_CONTRACT_GTX_CORE_DEVNET_ADDRESS=$USDC_ADDRESS
WETH_CONTRACT_GTX_CORE_DEVNET_ADDRESS=$WETH_ADDRESS

START_BLOCK=0
GTX_CORE_DEVNET_START_BLOCK=0
EOF

# Start indexer
DOTENV_CONFIG_PATH=.env.core-chain pnpm dev:core-chain
```

**✅ Success Check**: Indexer shows "Status: realtime" and "PoolManager:PoolCreated │ 2"

### Step 2: Setup Trading Bots
```bash
cd /Users/renaka/gtx/barista-bot-2

# Auto-configure with latest deployment addresses  
BALANCE_MANAGER=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.BalanceManager.address')
POOL_MANAGER=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.PoolManager.address')
GTX_ROUTER=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.GTXRouter.address')
USDC_ADDRESS=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.USDC.address')
WETH_ADDRESS=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.WETH.address')
GSUSDC_ADDRESS=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.gsUSDC.address')
GSWETH_ADDRESS=$(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.gsWETH.address')

# Update trading bot config
cat > .env << EOF
PROGRAM_MODE=trading-bots
CHAIN_ID=31337
RPC_URL=https://core-devnet.gtxdex.xyz

# Contract Addresses (from deployment)
PROXY_BALANCE_MANAGER=$BALANCE_MANAGER
PROXY_POOL_MANAGER=$POOL_MANAGER
PROXY_GTX_ROUTER=$GTX_ROUTER

# Token Addresses
USDC_TOKEN_ADDRESS=$USDC_ADDRESS
WETH_TOKEN_ADDRESS=$WETH_ADDRESS
GSUSDC_TOKEN_ADDRESS=$GSUSDC_ADDRESS
GSWETH_TOKEN_ADDRESS=$GSWETH_ADDRESS

# Trading Configuration
BASE_TOKEN_ADDRESS=$GSWETH_ADDRESS
QUOTE_TOKEN_ADDRESS=$GSUSDC_ADDRESS
USE_BALANCE_MANAGER=true
SKIP_TOKEN_MINTING=true

# Trading Bot Keys
PRIVATE_KEY_TRADER_BOT_1=0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
PRIVATE_KEY_TRADER_BOT_2=0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
PRIVATE_KEY_TRADER_BOT_3=0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e

# Market Maker Account
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Price Configuration
USE_BINANCE_PRICE=true
DEFAULT_PRICE=3000
LOG_LEVEL=info
EOF
```

### Step 3: Fund Accounts
```bash
# Still in /Users/renaka/gtx/barista-bot-2
# Auto-deposit both USDC and WETH to all accounts
pnpm deposit:local
```

**✅ Success Check**: See "🎉 All deposits completed successfully!" message

### Step 4: Start Market Maker
```bash
# Open new terminal - /Users/renaka/gtx/barista-bot-2
PROGRAM_MODE=market-maker LOG_LEVEL=info pnpm dev
```

**✅ Success Check**: See "Trade tx hash 0x..." messages (successful orders)

### Step 5: Start Trading Bots
```bash
# Open new terminal - /Users/renaka/gtx/barista-bot-2  
PROGRAM_MODE=trading-bots LOG_LEVEL=info pnpm dev
```

**✅ Success Check**: See "Market order placed successfully" messages

### Step 6: Verify Results
```bash
# Check how many trades were recorded
curl -s "http://localhost:42070/graphql" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ orderss { totalCount } tradess { totalCount } poolss { totalCount } }"}' \
  | jq '.data'
```

**✅ Success Check**: Should see orders > 0 and trades > 0

## 📊 Expected Results

After running for 2-3 minutes:
- **Pools**: 2 pools created (WETH/USDC pair + extras, created during deployment)
- **Orders**: 20-50 orders placed (market maker creates limit orders + trading bots place market orders)
- **Trades**: 10-30 trades executed (when market orders match against limit orders)
- **Indexer**: All events captured in real-time

**Why these numbers?**
- **Market maker** continuously places buy/sell limit orders (~2-5 per minute)
- **3 trading bots** place market orders every 30-60 seconds each
- **Trades happen** when market orders match existing limit orders on the book

## 🛑 Stop Everything
```bash
# Stop all processes
pkill -f "pnpm dev"
pkill -f "anvil"
```

## 🚨 Common Issues & Quick Fixes

### Indexer shows 0 pools
```bash
# Reset indexer start block
cd /Users/renaka/gtx/clob-indexer
pnpm db:drop-core
DOTENV_CONFIG_PATH=.env.core-chain pnpm dev:core-chain
```

### Trading bots can't place orders
```bash
# Check Balance Manager addresses match
cd /Users/renaka/gtx/barista-bot-2
echo "Config: $(grep PROXY_BALANCE_MANAGER .env)"
echo "Deployed: $(cat /Users/renaka/gtx/clob-dex/deployments/31337.json | jq -r '.BalanceManager.address')"
# Should be identical
```

### No trades happening
```bash
# Verify market maker is creating orders first
cd /Users/renaka/gtx/barista-bot-2
PROGRAM_MODE=market-maker LOG_LEVEL=info pnpm dev
# Wait for "Trade tx hash" messages before starting traders
```

## 🎯 Success Criteria

The test is successful when:
1. ✅ Indexer shows pools created  
2. ✅ Market maker places orders
3. ✅ Trading bots place orders
4. ✅ Trades are executed and recorded
5. ✅ GraphQL query returns orders > 0 and trades > 0

## 🔄 Full Reset (if needed)
```bash
# Stop everything
pkill -f "pnpm dev" && pkill -f "anvil"

# Restart Anvil
anvil --chain-id 31337 --port 8545

# Redeploy contracts  
cd /Users/renaka/gtx/clob-dex && ./deploy.sh

# Start from Step 1 again
```

## 📚 Next Steps

Once this quick test works:
- Scale up: Add more trading bots
- Monitor: Watch indexer GraphQL for activity
- Analyze: Study trade patterns and order book depth
- Optimize: Tune trading bot parameters

---

**💡 Tip**: Keep all terminals open to watch real-time logs. The system is working correctly when you see transaction hashes being generated across all components.