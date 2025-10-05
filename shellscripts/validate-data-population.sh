#!/bin/bash

# GTX Data Population Validation Script
# This script validates that data population was successful:
# - Both traders have deposited tokens successfully
# - OrderBook has liquidity (limit orders placed)
# - Trading events have been emitted (market orders executed)
# Output is logged to population.log

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="population.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🔍 Validating GTX Data Population..."
echo "Timestamp: $(date)"
echo ""

# Trader addresses
PRIMARY_TRADER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
SECONDARY_TRADER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

echo "=== Checking Required Tools ==="
if ! command -v jq >/dev/null 2>&1; then
    echo "❌ CRITICAL: jq is required but not installed."
    echo "   Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

if ! command -v cast >/dev/null 2>&1; then
    echo "❌ CRITICAL: cast (foundry) is required but not installed."
    echo "   Install foundry from: https://getfoundry.sh"
    exit 1
fi

echo "✅ Required tools available"
echo ""

echo "=== Checking Deployment Files ==="
CORE_DEPLOYMENT=""
if [ -f "deployments/31337.json" ]; then
    CORE_DEPLOYMENT="deployments/31337.json"
elif [ -f "deployments/gtx-anvil.json" ]; then
    CORE_DEPLOYMENT="deployments/gtx-anvil.json"
else
    echo "❌ CRITICAL: Core chain deployment file missing!"
    echo "   Expected: deployments/31337.json or deployments/gtx-anvil.json"
    echo "   Run deployment first: make validate-deployment"
    exit 1
fi

echo "✅ Core deployment file found: $CORE_DEPLOYMENT"
echo ""

# Extract contract addresses
BALANCE_MANAGER=$(jq -r '.PROXY_BALANCEMANAGER' $CORE_DEPLOYMENT)
POOL_MANAGER=$(jq -r '.PROXY_POOLMANAGER // .PoolManager' $CORE_DEPLOYMENT)
GSUSDC=$(jq -r '.gsUSDC' $CORE_DEPLOYMENT)
GSWETH=$(jq -r '.gsWETH' $CORE_DEPLOYMENT)
GSWBTC=$(jq -r '.gsWBTC' $CORE_DEPLOYMENT)

echo "=== Validating Trader Balances ==="
echo "Checking if both traders have deposited tokens and have synthetic token balances..."

check_trader_balance() {
    local TRADER=$1
    local TRADER_NAME=$2
    local TOKEN_ADDRESS=$3
    local TOKEN_NAME=$4
    local MIN_BALANCE=$5
    
    echo "Checking $TRADER_NAME $TOKEN_NAME balance..."
    
    BALANCE=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $TRADER $TOKEN_ADDRESS --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0")
    
    # Convert hex to decimal using cast to avoid overflow issues
    if [[ $BALANCE =~ ^0x[0-9a-fA-F]+$ ]]; then
        BALANCE_DECIMAL=$(echo "$BALANCE" | cast --to-dec 2>/dev/null || echo "0")
    else
        BALANCE_DECIMAL=0
    fi
    
    # Use awk for large number comparisons to avoid bash integer overflow
    if [ "$BALANCE_DECIMAL" = "0" ]; then
        echo "❌ CRITICAL: $TRADER_NAME has zero $TOKEN_NAME balance!"
        echo "   Trader: $TRADER"
        echo "   Token: $TOKEN_ADDRESS"
        echo "   This indicates deposits were not successful"
        echo "   Fix: Run data population first: follow DATA_POPULATION.md"
        return 1
    elif awk -v bal="$BALANCE_DECIMAL" -v min="$MIN_BALANCE" 'BEGIN { exit (bal < min) ? 0 : 1 }'; then
        echo "⚠️  WARNING: $TRADER_NAME has low $TOKEN_NAME balance: $BALANCE_DECIMAL"
        echo "   Expected minimum: $MIN_BALANCE"
        echo "   This may indicate incomplete deposits"
        return 1
    else
        echo "✅ $TRADER_NAME $TOKEN_NAME balance: $BALANCE_DECIMAL"
        return 0
    fi
}

# Check primary trader balances (should have deposited and used some for trading)
BALANCES_OK=true

if ! check_trader_balance $PRIMARY_TRADER "Primary trader" $GSUSDC "gsUSDC" 1000000; then
    BALANCES_OK=false
fi

if ! check_trader_balance $PRIMARY_TRADER "Primary trader" $GSWETH "gsWETH" 1000000000000000; then
    BALANCES_OK=false
fi

# Check secondary trader balances (should have deposited and used some for trading)
if ! check_trader_balance $SECONDARY_TRADER "Secondary trader" $GSUSDC "gsUSDC" 1000000; then
    BALANCES_OK=false
fi

if ! check_trader_balance $SECONDARY_TRADER "Secondary trader" $GSWETH "gsWETH" 1000000000000000; then
    BALANCES_OK=false
fi

if [ "$BALANCES_OK" = false ]; then
    echo "❌ CRITICAL: Trader balances indicate deposits were not successful!"
    echo "   Run the complete data population flow first"
    echo "   Continuing with event validation to show complete status..."
    echo ""
else
    echo "✅ Both traders have synthetic token balances (deposits successful)"
    echo ""
fi

echo "=== Validating OrderBook Liquidity ==="
echo "Checking if limit orders have been placed to create liquidity..."

if [ "$POOL_MANAGER" = "null" ] || [ -z "$POOL_MANAGER" ] || [ "$POOL_MANAGER" = "0x0000000000000000000000000000000000000000" ]; then
    echo "❌ CRITICAL: PoolManager not found!"
    echo "   Cannot validate orderbook liquidity without PoolManager"
    echo "   Ensure deployment is complete first"
    exit 1
fi

check_pool_liquidity() {
    local TOKEN1=$1
    local TOKEN2=$2
    local POOL_NAME=$3
    
    echo "Checking $POOL_NAME liquidity..."
    
    # Check if pool exists first
    POOL_EXISTS=$(cast call $POOL_MANAGER "poolExists(address,address)" $TOKEN1 $TOKEN2 --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
    
    if [[ $POOL_EXISTS != *"0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "❌ CRITICAL: $POOL_NAME pool does not exist!"
        echo "   Pool creation required before adding liquidity"
        return 1
    fi
    
    # Get liquidity score
    LIQUIDITY_SCORE=$(cast call $POOL_MANAGER "getPoolLiquidityScore(address,address)" $TOKEN1 $TOKEN2 --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0")
    
    # Convert hex to decimal if it's a valid hex number using cast to avoid overflow
    if [[ $LIQUIDITY_SCORE =~ ^0x[0-9a-fA-F]+$ ]]; then
        LIQUIDITY_DECIMAL=$(echo "$LIQUIDITY_SCORE" | cast --to-dec 2>/dev/null || echo "0")
    else
        LIQUIDITY_DECIMAL=0
    fi
    
    if [ "$LIQUIDITY_DECIMAL" = "0" ]; then
        echo "❌ CRITICAL: $POOL_NAME has no liquidity!"
        echo "   No limit orders have been placed"
        echo "   Fix: Run 'PRIVATE_KEY=\$PRIVATE_KEY make fill-orderbook network=gtx_core_devnet'"
        return 1
    else
        echo "✅ $POOL_NAME has liquidity score: $LIQUIDITY_DECIMAL"
        return 0
    fi
}

LIQUIDITY_OK=true

if ! check_pool_liquidity $GSWETH $GSUSDC "gsWETH/gsUSDC"; then
    LIQUIDITY_OK=false
fi

if ! check_pool_liquidity $GSWBTC $GSUSDC "gsWBTC/gsUSDC"; then
    # WBTC liquidity is optional, just warn
    echo "⚠️  WARNING: gsWBTC/gsUSDC pool has no liquidity (this is optional)"
fi

if [ "$LIQUIDITY_OK" = false ]; then
    echo "❌ CRITICAL: OrderBook has no liquidity!"
    echo "   Limit orders have not been placed successfully"
    echo "   Run fill-orderbook to create liquidity first"
    echo "   Continuing with event validation..."
    echo ""
else
    echo "✅ OrderBook has liquidity (limit orders placed successfully)"
    echo ""
fi

echo "=== Validating Trading Activity ==="
echo "Checking for recent trading events to verify market orders were executed..."

# Get the latest block number
LATEST_BLOCK=$(cast block-number --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0")

if [ "$LATEST_BLOCK" -eq 0 ]; then
    echo "❌ CRITICAL: Cannot get latest block number!"
    echo "   RPC connection issue or chain not running"
    exit 1
fi

echo "Latest block: $LATEST_BLOCK"

# Look for recent trading events in the last 100 blocks
FROM_BLOCK=$((LATEST_BLOCK - 100))
if [ $FROM_BLOCK -lt 1 ]; then
    FROM_BLOCK=1
fi

echo "Searching for trading events from block $FROM_BLOCK to $LATEST_BLOCK..."

# Get OrderBook addresses for gsWETH/gsUSDC pool
echo "Getting OrderBook address for gsWETH/gsUSDC pool..."
POOL_DATA=$(cast call $POOL_MANAGER "getPool((address,address))" "($GSWETH,$GSUSDC)" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "")

if [ -z "$POOL_DATA" ] || [ "$POOL_DATA" = "0x" ]; then
    echo "❌ CRITICAL: Cannot get pool data for gsWETH/gsUSDC!"
    echo "   Pool may not exist or PoolManager call failed"
    exit 1
fi

# Extract OrderBook address from pool data (first 32 bytes after removing 0x prefix)
# Pool struct: (IOrderBook orderBook, Currency baseCurrency, Currency quoteCurrency)
ORDERBOOK_ADDR="0x${POOL_DATA:26:40}"  # Extract 20-byte address from 32-byte slot

if [ "$ORDERBOOK_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
    echo "❌ CRITICAL: OrderBook address is zero!"
    echo "   Pool may not be properly initialized"
    exit 1
fi

echo "Found OrderBook address: $ORDERBOOK_ADDR"

# Check for OrderPlaced events from OrderBook (correct IOrderBook events)
ORDER_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block $LATEST_BLOCK --address $ORDERBOOK_ADDR "OrderPlaced(uint48,address,uint8,uint128,uint128,uint48,bool,uint8)" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null | wc -l || echo "0")

if [ "$ORDER_EVENTS" -gt 0 ]; then
    echo "✅ Found $ORDER_EVENTS OrderPlaced events (limit orders created)"
else
    echo "⚠️  WARNING: No OrderPlaced events found in recent blocks"
    echo "   This may indicate fill-orderbook was not run recently"
fi

# Check for OrderMatched events from OrderBook (correct IOrderBook events) 
MATCHED_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block $LATEST_BLOCK --address $ORDERBOOK_ADDR "OrderMatched(address,uint48,uint48,uint8,uint48,uint128,uint128)" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null | wc -l || echo "0")

if [ "$MATCHED_EVENTS" -gt 0 ]; then
    echo "✅ Found $MATCHED_EVENTS OrderMatched events (orders matched)"
    echo "✅ Trading activity confirmed - orders have been matched"
else
    echo "⚠️  WARNING: No OrderMatched events found in recent blocks"
    echo "   This may indicate:"
    echo "   1. Market orders failed due to MemoryOOG (use PRIVATE_KEY_2)"
    echo "   2. Market orders haven't been run yet"
    echo "   3. Orders were placed too long ago (outside recent blocks)"
    echo ""
    echo "   To execute market orders:"
    echo "   PRIVATE_KEY_2=\$PRIVATE_KEY_2 make market-order network=gtx_core_devnet"
fi

# Check for UpdateOrder events (indicates orders being filled)
UPDATE_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block $LATEST_BLOCK --address $ORDERBOOK_ADDR "UpdateOrder(uint48,uint48,uint128,uint8)" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null | wc -l || echo "0")

if [ "$UPDATE_EVENTS" -gt 0 ]; then
    echo "✅ Found $UPDATE_EVENTS UpdateOrder events (orders being filled/updated)"
fi

# Check for BalanceUpdated events (indicates successful deposits)
BALANCE_EVENTS=$(cast logs --from-block $FROM_BLOCK --to-block $LATEST_BLOCK --address $BALANCE_MANAGER "BalanceUpdated(address,address,uint256)" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null | wc -l || echo "0")

if [ "$BALANCE_EVENTS" -gt 0 ]; then
    echo "✅ Found $BALANCE_EVENTS BalanceUpdated events (deposits successful)"
else
    echo "⚠️  WARNING: No BalanceUpdated events found in recent blocks"
    echo "   Deposits may have occurred outside the recent block range"
fi

echo ""

echo "=== Data Population Status Summary ==="

TOTAL_ISSUES=0

# Count critical issues
if [ "$BALANCES_OK" = false ]; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi

if [ "$LIQUIDITY_OK" = false ]; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi

if [ "$TOTAL_ISSUES" -eq 0 ]; then
    echo "🎉 DATA POPULATION VALIDATION PASSED!"
    echo "✅ Both traders have synthetic token balances"
    echo "✅ OrderBook has liquidity (limit orders placed)"
    
    if [ "$MATCHED_EVENTS" -gt 0 ]; then
        echo "✅ Market orders have been executed successfully"
        echo "✅ Complete trading flow verified"
    else
        echo "⚠️  Market orders may not have been executed yet"
        echo "   Run: PRIVATE_KEY_2=\$PRIVATE_KEY_2 make market-order network=gtx_core_devnet"
    fi
    
    echo ""
    echo "📊 Population Summary:"
    echo "   • Primary trader: Has deposited and created liquidity"
    echo "   • Secondary trader: Has deposited tokens"
    echo "   • OrderBook: Has active limit orders"
    echo "   • Events: $ORDER_EVENTS orders placed, $MATCHED_EVENTS orders matched, $UPDATE_EVENTS order updates"
    echo ""
    echo "✅ System is populated and ready for trading demonstrations"
    
else
    echo "❌ DATA POPULATION VALIDATION FAILED!"
    echo "   $TOTAL_ISSUES critical issues found"
    echo ""
    echo "🔧 Recommended fixes:"
    echo "   1. Ensure deployment is complete: make validate-deployment"
    echo "   2. Run complete data population: follow DATA_POPULATION.md"
    echo "   3. Check trader private keys are set correctly"
    echo "   4. Verify both traders have sufficient token balances"
fi

echo ""
echo "🔍 Quick Debug Commands:"
echo "   # Check primary trader balances"
echo "   cast call $BALANCE_MANAGER \"getBalance(address,address)\" $PRIMARY_TRADER $GSUSDC --rpc-url https://core-devnet.gtxdex.xyz"
echo "   cast call $BALANCE_MANAGER \"getBalance(address,address)\" $PRIMARY_TRADER $GSWETH --rpc-url https://core-devnet.gtxdex.xyz"
echo ""
echo "   # Check secondary trader balances"
echo "   cast call $BALANCE_MANAGER \"getBalance(address,address)\" $SECONDARY_TRADER $GSUSDC --rpc-url https://core-devnet.gtxdex.xyz"
echo "   cast call $BALANCE_MANAGER \"getBalance(address,address)\" $SECONDARY_TRADER $GSWETH --rpc-url https://core-devnet.gtxdex.xyz"
echo ""
echo "   # Check pool liquidity"
echo "   cast call $POOL_MANAGER \"getPoolLiquidityScore(address,address)\" $GSWETH $GSUSDC --rpc-url https://core-devnet.gtxdex.xyz"
echo ""
echo "   # Get OrderBook address for gsWETH/gsUSDC"
echo "   cast call $POOL_MANAGER \"getPool((address,address))\" \"($GSWETH,$GSUSDC)\" --rpc-url https://core-devnet.gtxdex.xyz"
echo ""
echo "Validation completed at: $(date)"

# Exit with error code if there were critical issues
if [ "$TOTAL_ISSUES" -gt 0 ]; then
    exit 1
fi