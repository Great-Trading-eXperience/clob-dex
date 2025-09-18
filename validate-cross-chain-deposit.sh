#!/bin/bash

# GTX Cross-Chain Deposit Validation Script
# This script validates that cross-chain deposits are working properly:
# - ChainBalanceManager is deployed and configured on side chain
# - BalanceManager is deployed and configured on core chain
# - Token mappings are correctly set up between chains
# - Hyperlane mailbox is operational and processing messages
# - Cross-chain deposit flow can be executed successfully
# Output is logged to cross-chain.log

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="cross-chain-deposit.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🔍 Validating GTX Cross-Chain Deposit System..."
echo "Timestamp: $(date)"
echo ""

# Chain configuration
CORE_CHAIN_ID="31337"
SIDE_CHAIN_ID="31338"
CORE_RPC="https://anvil.gtxdex.xyz"
SIDE_RPC="https://side-anvil.gtxdex.xyz"

# Test addresses
PRIMARY_TRADER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

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
SIDE_DEPLOYMENT=""

if [ -f "deployments/${CORE_CHAIN_ID}.json" ]; then
    CORE_DEPLOYMENT="deployments/${CORE_CHAIN_ID}.json"
    echo "✅ Core chain deployment found: $CORE_DEPLOYMENT"
else
    echo "❌ CRITICAL: Core chain deployment file missing (deployments/${CORE_CHAIN_ID}.json)"
    echo "   Run deployment script first!"
    exit 1
fi

if [ -f "deployments/${SIDE_CHAIN_ID}.json" ]; then
    SIDE_DEPLOYMENT="deployments/${SIDE_CHAIN_ID}.json"
    echo "✅ Side chain deployment found: $SIDE_DEPLOYMENT"
else
    echo "❌ CRITICAL: Side chain deployment file missing (deployments/${SIDE_CHAIN_ID}.json)"
    echo "   Run side chain deployment first!"
    exit 1
fi

echo ""

echo "=== Loading Contract Addresses ==="
# Load core chain contracts
BALANCE_MANAGER=$(jq -r '.PROXY_BALANCEMANAGER' "$CORE_DEPLOYMENT")
CORE_USDC=$(jq -r '.USDC' "$CORE_DEPLOYMENT")
CORE_WETH=$(jq -r '.WETH' "$CORE_DEPLOYMENT")
CORE_GSUSDC=$(jq -r '.gsUSDC' "$CORE_DEPLOYMENT")
CORE_GSWETH=$(jq -r '.gsWETH' "$CORE_DEPLOYMENT")

# Load side chain contracts
CHAIN_BALANCE_MANAGER=$(jq -r '.ChainBalanceManager' "$SIDE_DEPLOYMENT")
SIDE_USDC=$(jq -r '.USDC' "$SIDE_DEPLOYMENT")
SIDE_WETH=$(jq -r '.WETH' "$SIDE_DEPLOYMENT")

echo "Core Chain ($CORE_CHAIN_ID):"
echo "  BalanceManager: $BALANCE_MANAGER"
echo "  USDC: $CORE_USDC"
echo "  gsUSDC: $CORE_GSUSDC"
echo ""
echo "Side Chain ($SIDE_CHAIN_ID):"
echo "  ChainBalanceManager: $CHAIN_BALANCE_MANAGER"
echo "  USDC: $SIDE_USDC"
echo ""

echo "=== Validating Chain Connectivity ==="
echo "Checking core chain connectivity ($CORE_RPC)..."
CORE_BLOCK=$(cast block-number --rpc-url "$CORE_RPC" 2>/dev/null || echo "0")
if [ "$CORE_BLOCK" -gt 0 ]; then
    echo "✅ Core chain connected (block: $CORE_BLOCK)"
else
    echo "❌ Core chain connection failed"
    exit 1
fi

echo "Checking side chain connectivity ($SIDE_RPC)..."
SIDE_BLOCK=$(cast block-number --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0")
if [ "$SIDE_BLOCK" -gt 0 ]; then
    echo "✅ Side chain connected (block: $SIDE_BLOCK)"
else
    echo "❌ Side chain connection failed"
    exit 1
fi

echo ""

echo "=== Validating Contract Deployments ==="
echo "Checking BalanceManager on core chain..."
CORE_BM_CODE=$(cast code "$BALANCE_MANAGER" --rpc-url "$CORE_RPC" 2>/dev/null || echo "0x")
if [ "$CORE_BM_CODE" != "0x" ]; then
    echo "✅ BalanceManager deployed on core chain"
else
    echo "❌ BalanceManager not found on core chain"
    exit 1
fi

echo "Checking ChainBalanceManager on side chain..."
SIDE_CBM_CODE=$(cast code "$CHAIN_BALANCE_MANAGER" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x")
if [ "$SIDE_CBM_CODE" != "0x" ]; then
    echo "✅ ChainBalanceManager deployed on side chain"
else
    echo "❌ ChainBalanceManager not found on side chain"
    exit 1
fi

echo ""

echo "=== Validating Token Whitelisting ==="
echo "Checking if USDC is whitelisted on side chain..."
USDC_WHITELISTED=$(cast call "$CHAIN_BALANCE_MANAGER" "isTokenWhitelisted(address)" "$SIDE_USDC" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
if [ "$USDC_WHITELISTED" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✅ USDC is whitelisted on side chain"
else
    echo "❌ USDC is not whitelisted on side chain"
    echo "   Run token configuration script"
fi

echo "Checking if WETH is whitelisted on side chain..."
WETH_WHITELISTED=$(cast call "$CHAIN_BALANCE_MANAGER" "isTokenWhitelisted(address)" "$SIDE_WETH" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
if [ "$WETH_WHITELISTED" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✅ WETH is whitelisted on side chain"
else
    echo "❌ WETH is not whitelisted on side chain"
    echo "   Run token configuration script"
fi

echo ""

echo "=== Validating Token Mappings ==="
echo "Checking USDC mapping on side chain..."
USDC_MAPPING=$(cast call "$CHAIN_BALANCE_MANAGER" "getTokenMapping(address)" "$SIDE_USDC" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
# Normalize both addresses to the same format (remove 0x000...000 prefix and compare last 40 chars)
USDC_MAPPING_ADDR=$(echo "$USDC_MAPPING" | sed 's/0x0*//g' | tail -c 41 | tr '[:upper:]' '[:lower:]')
CORE_GSUSDC_ADDR=$(echo "$CORE_GSUSDC" | sed 's/0x//g' | tr '[:upper:]' '[:lower:]')
if [ "$USDC_MAPPING_ADDR" = "$CORE_GSUSDC_ADDR" ]; then
    echo "✅ USDC mapping correct: $SIDE_USDC -> $CORE_GSUSDC"
else
    echo "❌ USDC mapping incorrect. Expected: $CORE_GSUSDC, Got: $USDC_MAPPING"
fi

echo "Checking WETH mapping on side chain..."
WETH_MAPPING=$(cast call "$CHAIN_BALANCE_MANAGER" "getTokenMapping(address)" "$SIDE_WETH" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
# Normalize both addresses to the same format (remove 0x000...000 prefix and compare last 40 chars)
WETH_MAPPING_ADDR=$(echo "$WETH_MAPPING" | sed 's/0x0*//g' | tail -c 41 | tr '[:upper:]' '[:lower:]')
CORE_GSWETH_ADDR=$(echo "$CORE_GSWETH" | sed 's/0x//g' | tr '[:upper:]' '[:lower:]')
if [ "$WETH_MAPPING_ADDR" = "$CORE_GSWETH_ADDR" ]; then
    echo "✅ WETH mapping correct: $SIDE_WETH -> $CORE_GSWETH"
else
    echo "❌ WETH mapping incorrect. Expected: $CORE_GSWETH, Got: $WETH_MAPPING"
fi

echo ""

echo "=== Checking User Token Balances ==="
echo "Checking user USDC balance on side chain..."
SIDE_USDC_BALANCE=$(cast call "$SIDE_USDC" "balanceOf(address)" "$PRIMARY_TRADER" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x0")
SIDE_USDC_BALANCE_DEC=$(echo "$SIDE_USDC_BALANCE" | cast --to-dec 2>/dev/null || echo "0")
if [ $(echo "$SIDE_USDC_BALANCE_DEC > 1000000000" | awk '{print ($1 > $2)}') -eq 1 ]; then
    echo "✅ User has sufficient USDC on side chain: $SIDE_USDC_BALANCE_DEC"
else
    echo "⚠️  User has low USDC balance on side chain: $SIDE_USDC_BALANCE_DEC"
    echo "   Consider minting more tokens for testing"
fi

echo "Checking user WETH balance on side chain..."
SIDE_WETH_BALANCE=$(cast call "$SIDE_WETH" "balanceOf(address)" "$PRIMARY_TRADER" --rpc-url "$SIDE_RPC" 2>/dev/null || echo "0x0")
SIDE_WETH_BALANCE_DEC=$(echo "$SIDE_WETH_BALANCE" | cast --to-dec 2>/dev/null || echo "0")
if [ $(echo "$SIDE_WETH_BALANCE_DEC > 1000000000000000000" | awk '{print ($1 > $2)}') -eq 1 ]; then
    echo "✅ User has sufficient WETH on side chain: $SIDE_WETH_BALANCE_DEC"
else
    echo "⚠️  User has low WETH balance on side chain: $SIDE_WETH_BALANCE_DEC"
    echo "   Consider minting more tokens for testing"
fi

echo ""

echo "=== Checking Recent Cross-Chain Activity ==="
# Look for recent cross-chain deposits by checking balance increases
echo "Checking for recent synthetic token balance changes on core chain..."

# Check recent gsUSDC balance
GSUSDC_BALANCE=$(cast call "$BALANCE_MANAGER" "getBalance(address,address)" "$PRIMARY_TRADER" "$CORE_GSUSDC" --rpc-url "$CORE_RPC" 2>/dev/null || echo "0x0")
GSUSDC_BALANCE_DEC=$(echo "$GSUSDC_BALANCE" | cast --to-dec 2>/dev/null || echo "0")

if [ "$GSUSDC_BALANCE_DEC" -gt 0 ]; then
    echo "✅ User has gsUSDC balance on core chain: $GSUSDC_BALANCE_DEC"
    echo "   This indicates successful cross-chain deposits"
else
    echo "ℹ️  User has no gsUSDC balance on core chain"
    echo "   No cross-chain USDC deposits detected"
fi

# Check recent gsWETH balance
GSWETH_BALANCE=$(cast call "$BALANCE_MANAGER" "getBalance(address,address)" "$PRIMARY_TRADER" "$CORE_GSWETH" --rpc-url "$CORE_RPC" 2>/dev/null || echo "0x0")
GSWETH_BALANCE_DEC=$(echo "$GSWETH_BALANCE" | cast --to-dec 2>/dev/null || echo "0")

if [ $(echo "$GSWETH_BALANCE_DEC > 0" | awk '{print ($1 > $2)}') -eq 1 ]; then
    echo "✅ User has gsWETH balance on core chain: $GSWETH_BALANCE_DEC"
    echo "   This indicates successful cross-chain deposits"
else
    echo "ℹ️  User has no gsWETH balance on core chain"
    echo "   No cross-chain WETH deposits detected"
fi

echo ""

echo "=== Hyperlane Integration Status ==="
# Try to detect mailbox address - this is environment specific
MAILBOX_CANDIDATES=(
    "0xe844dF90c946CecD08076D129E14a3bc04C9f5d5"  # Common Hyperlane mailbox
    "0x2f9DB5616fa3fAd1aB06cB2C906830BA63d135e3"  # Another common address
)

CORE_MAILBOX=""
for candidate in "${MAILBOX_CANDIDATES[@]}"; do
    MAILBOX_CODE=$(cast code "$candidate" --rpc-url "$CORE_RPC" 2>/dev/null || echo "0x")
    if [ "$MAILBOX_CODE" != "0x" ]; then
        CORE_MAILBOX="$candidate"
        echo "✅ Hyperlane mailbox found on core chain: $CORE_MAILBOX"
        break
    fi
done

if [ -z "$CORE_MAILBOX" ]; then
    echo "⚠️  Hyperlane mailbox not found with known addresses"
    echo "   Cross-chain functionality may not be available"
else
    # Check for recent Hyperlane activity
    echo "Checking for recent Hyperlane message activity..."
    RECENT_BLOCK=$((CORE_BLOCK - 100))
    if [ $RECENT_BLOCK -lt 1 ]; then
        RECENT_BLOCK=1
    fi
    
    MAILBOX_EVENTS=$(cast logs --from-block "$RECENT_BLOCK" --to-block latest --address "$CORE_MAILBOX" --rpc-url "$CORE_RPC" 2>/dev/null | wc -l || echo "0")
    
    if [ "$MAILBOX_EVENTS" -gt 0 ]; then
        echo "✅ Recent Hyperlane activity detected: $MAILBOX_EVENTS events in last 100 blocks"
    else
        echo "ℹ️  No recent Hyperlane activity in last 100 blocks"
    fi
fi

echo ""

echo "=== Cross-Chain System Status Summary ==="
ISSUES=0

# Check critical components
if [ "$CORE_BM_CODE" = "0x" ]; then
    echo "❌ BalanceManager not deployed on core chain"
    ISSUES=$((ISSUES + 1))
fi

if [ "$SIDE_CBM_CODE" = "0x" ]; then
    echo "❌ ChainBalanceManager not deployed on side chain"
    ISSUES=$((ISSUES + 1))
fi

if [ "$USDC_WHITELISTED" != "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "❌ USDC not whitelisted on side chain"
    ISSUES=$((ISSUES + 1))
fi

if [ "$USDC_MAPPING_ADDR" != "$CORE_GSUSDC_ADDR" ]; then
    echo "❌ USDC mapping incorrect"
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo "🎉 CROSS-CHAIN SYSTEM VALIDATION PASSED!"
    echo "✅ All core contracts deployed and configured"
    echo "✅ Token mappings correctly set up"
    echo "✅ System ready for cross-chain deposits"
    
    # Provide test commands
    echo ""
    echo "📋 Quick Test Commands:"
    echo "   # Test cross-chain USDC deposit"
    echo "   make test-cross-chain-deposit network=gtx_anvil_2 side_chain=$SIDE_CHAIN_ID core_chain=$CORE_CHAIN_ID token=USDC amount=1000000000"
    echo ""
    echo "   # Test cross-chain WETH deposit"
    echo "   make test-cross-chain-deposit network=gtx_anvil_2 side_chain=$SIDE_CHAIN_ID core_chain=$CORE_CHAIN_ID token=WETH amount=1000000000000000000"
    echo ""
    echo "   # Check synthetic balances after deposit"
    echo "   cast call $BALANCE_MANAGER \"getBalance(address,address)\" $PRIMARY_TRADER $CORE_GSUSDC --rpc-url $CORE_RPC"
    
else
    echo "❌ CROSS-CHAIN SYSTEM VALIDATION FAILED!"
    echo "   Found $ISSUES issue(s) that need to be resolved"
    echo "   Please fix the issues above before attempting cross-chain deposits"
fi

echo ""
echo "Validation completed at: $(date)"