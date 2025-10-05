#!/bin/bash

# GTX Two-Chain Deployment Validation Script
# This script validates that all contracts are properly deployed and configured
# Output is logged to deployment.log

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="deployment.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🔍 Validating GTX Two-Chain Deployment..."
echo "Timestamp: $(date)"
echo ""

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

echo "=== Validating Deployment Files ==="
# Check for either naming scheme (chain ID or chain name)
CORE_DEPLOYMENT=""
SIDE_DEPLOYMENT=""

if [ -f "deployments/31337.json" ]; then
    CORE_DEPLOYMENT="deployments/31337.json"
elif [ -f "deployments/gtx-anvil.json" ]; then
    CORE_DEPLOYMENT="deployments/gtx-anvil.json"
else
    echo "❌ CRITICAL: Core chain deployment file missing!"
    echo "   Expected: deployments/31337.json or deployments/gtx-anvil.json"
    echo "   Run: make deploy-core-chain-trading network=gtx_core_devnet"
    exit 1
fi

if [ -f "deployments/31338.json" ]; then
    SIDE_DEPLOYMENT="deployments/31338.json"
elif [ -f "deployments/gtx-anvil-2.json" ]; then
    SIDE_DEPLOYMENT="deployments/gtx-anvil-2.json"
else
    echo "❌ CRITICAL: Side chain deployment file missing!"
    echo "   Expected: deployments/31338.json or deployments/gtx-anvil-2.json"
    echo "   Run: make deploy-side-chain-bm network=gtx_side_devnet"
    exit 1
fi

echo "✅ Both deployment files exist"
echo ""

echo "=== Validating Core Chain Contracts ==="
# Use consistent PROXY_ naming for core contracts
for contract_pair in "BalanceManager:PROXY_BALANCEMANAGER" "TokenRegistry:PROXY_TOKENREGISTRY" "SyntheticTokenFactory:PROXY_SYNTHETICTOKENFACTORY" "gsUSDC:gsUSDC" "gsWETH:gsWETH" "gsWBTC:gsWBTC"; do
    DISPLAY_NAME=$(echo $contract_pair | cut -d: -f1)
    ACTUAL_KEY=$(echo $contract_pair | cut -d: -f2)
    ADDRESS=$(jq -r ".$ACTUAL_KEY" $CORE_DEPLOYMENT 2>/dev/null)
    if [ "$ADDRESS" = "null" ] || [ -z "$ADDRESS" ] || [ "$ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
        echo "❌ CRITICAL: $DISPLAY_NAME missing or zero address in $CORE_DEPLOYMENT"
        echo "   Core chain deployment incomplete. Redeploy core chain first."
        exit 1
    fi
    
    CODE=$(cast code $ADDRESS --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x")
    if [ "$CODE" = "0x" ]; then
        echo "❌ CRITICAL: $DISPLAY_NAME at $ADDRESS has no code on core chain!"
        echo "   Contract not deployed. Redeploy core chain first."
        exit 1
    fi
    
    echo "✅ $DISPLAY_NAME validated: $ADDRESS"
done
echo ""

echo "=== Validating Side Chain Contracts ==="
for contract in ChainBalanceManager USDC WETH WBTC; do
    ADDRESS=$(jq -r ".$contract" $SIDE_DEPLOYMENT 2>/dev/null)
    if [ "$ADDRESS" = "null" ] || [ -z "$ADDRESS" ] || [ "$ADDRESS" = "0x0000000000000000000000000000000000000000" ]; then
        echo "❌ CRITICAL: $contract missing or zero address in $SIDE_DEPLOYMENT"
        echo "   Side chain deployment incomplete. Redeploy side chain first."
        exit 1
    fi
    
    CODE=$(cast code $ADDRESS --rpc-url https://side-devnet.gtxdex.xyz 2>/dev/null || echo "0x")
    if [ "$CODE" = "0x" ]; then
        echo "❌ CRITICAL: $contract at $ADDRESS has no code on side chain!"
        echo "   Contract not deployed. Redeploy side chain first."
        exit 1
    fi
    
    echo "✅ $contract validated: $ADDRESS"
done
echo ""

echo "=== Validating Token Mappings ==="
SIDE_CHAINBM=$(jq -r '.ChainBalanceManager' $SIDE_DEPLOYMENT)

for token_pair in "USDC:gsUSDC" "WETH:gsWETH" "WBTC:gsWBTC"; do
    SIDE_TOKEN_KEY=$(echo $token_pair | cut -d: -f1)
    CORE_TOKEN_KEY=$(echo $token_pair | cut -d: -f2)
    SIDE_TOKEN=$(jq -r ".$SIDE_TOKEN_KEY" $SIDE_DEPLOYMENT)
    CORE_SYNTHETIC=$(jq -r ".$CORE_TOKEN_KEY" $CORE_DEPLOYMENT)
    
    MAPPED_SYNTHETIC=$(cast call $SIDE_CHAINBM "getTokenMapping(address)" $SIDE_TOKEN --rpc-url https://side-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    
    # Extract actual address from the 32-byte return value
    if [[ $MAPPED_SYNTHETIC == 0x000000000000000000000000* ]]; then
        MAPPED_ADDR="0x${MAPPED_SYNTHETIC:26}"  # Extract last 20 bytes (40 hex chars)
    else
        MAPPED_ADDR="$MAPPED_SYNTHETIC"
    fi
    
    if [ "$MAPPED_ADDR" = "0x0000000000000000000000000000000000000000" ]; then
        echo "❌ CRITICAL: $SIDE_TOKEN_KEY token mapping not set in ChainBalanceManager!"
        echo "   Side $SIDE_TOKEN_KEY: $SIDE_TOKEN"
        echo "   Expected synthetic: $CORE_SYNTHETIC"
        echo "   Fix: Run 'make configure-cross-chain-tokens network=gtx_core_devnet'"
        exit 1
    fi
    
    MAPPED_LOWER=$(echo $MAPPED_ADDR | tr '[:upper:]' '[:lower:]')
    EXPECTED_LOWER=$(echo $CORE_SYNTHETIC | tr '[:upper:]' '[:lower:]')
    
    if [ "$MAPPED_LOWER" != "$EXPECTED_LOWER" ]; then
        echo "❌ CRITICAL: $SIDE_TOKEN_KEY token mapping mismatch!"
        echo "   Side $SIDE_TOKEN_KEY: $SIDE_TOKEN"
        echo "   Expected synthetic: $CORE_SYNTHETIC"
        echo "   Actual mapping: $MAPPED_ADDR"
        echo "   Fix: Run 'make configure-cross-chain-tokens network=gtx_core_devnet'"
        exit 1
    fi
    
    echo "✅ $SIDE_TOKEN_KEY mapping validated: $SIDE_TOKEN -> $MAPPED_ADDR"
done
echo ""

echo "=== Validating BalanceManager Configuration ==="
BALANCE_MANAGER=$(jq -r '.PROXY_BALANCEMANAGER' $CORE_DEPLOYMENT)
TOKEN_REGISTRY=$(jq -r '.PROXY_TOKENREGISTRY' $CORE_DEPLOYMENT)

CONFIGURED_REGISTRY=$(cast call $BALANCE_MANAGER "getTokenRegistry()" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

# Extract actual address from the 32-byte return value if needed
if [[ $CONFIGURED_REGISTRY == 0x000000000000000000000000* ]] && [ ${#CONFIGURED_REGISTRY} -eq 66 ]; then
    CONFIGURED_ADDR="0x${CONFIGURED_REGISTRY:26}"  # Extract last 20 bytes (40 hex chars)
else
    CONFIGURED_ADDR="$CONFIGURED_REGISTRY"
fi

CONFIGURED_LOWER=$(echo $CONFIGURED_ADDR | tr '[:upper:]' '[:lower:]')
EXPECTED_REGISTRY_LOWER=$(echo $TOKEN_REGISTRY | tr '[:upper:]' '[:lower:]')

if [ "$CONFIGURED_LOWER" != "$EXPECTED_REGISTRY_LOWER" ]; then
    echo "❌ CRITICAL: BalanceManager TokenRegistry not configured correctly!"
    echo "   BalanceManager: $BALANCE_MANAGER"
    echo "   Expected TokenRegistry: $TOKEN_REGISTRY"
    echo "   Configured TokenRegistry: $CONFIGURED_ADDR"
    echo "   Fix: Run 'make configure-cross-chain-tokens network=gtx_core_devnet'"
    exit 1
fi

echo "✅ BalanceManager TokenRegistry validated: $CONFIGURED_ADDR"

echo "=== Validating TokenRegistry Local Mappings ==="
echo "Checking if TokenRegistry correctly maps regular tokens to synthetic tokens for local deposits..."

for token_pair in "USDC:gsUSDC" "WETH:gsWETH" "WBTC:gsWBTC"; do
    REGULAR_TOKEN_KEY=$(echo $token_pair | cut -d: -f1)
    SYNTHETIC_TOKEN_KEY=$(echo $token_pair | cut -d: -f2)
    
    # Get addresses from core deployment (both regular and synthetic tokens are on core chain)
    REGULAR_TOKEN=$(jq -r ".$REGULAR_TOKEN_KEY" $CORE_DEPLOYMENT)
    EXPECTED_SYNTHETIC=$(jq -r ".$SYNTHETIC_TOKEN_KEY" $CORE_DEPLOYMENT)
    
    if [ "$REGULAR_TOKEN" = "null" ] || [ -z "$REGULAR_TOKEN" ] || [ "$REGULAR_TOKEN" = "0x0000000000000000000000000000000000000000" ]; then
        echo "❌ CRITICAL: $REGULAR_TOKEN_KEY token address missing in core deployment!"
        echo "   This is required for local deposit functionality"
        exit 1
    fi
    
    if [ "$EXPECTED_SYNTHETIC" = "null" ] || [ -z "$EXPECTED_SYNTHETIC" ] || [ "$EXPECTED_SYNTHETIC" = "0x0000000000000000000000000000000000000000" ]; then
        echo "❌ CRITICAL: $SYNTHETIC_TOKEN_KEY token address missing in core deployment!"
        echo "   This is required for local deposit functionality"
        exit 1
    fi
    
    echo "Checking local mapping for $REGULAR_TOKEN_KEY..."
    
    # Check if local mapping is active (sourceChain = targetChain = 31337)
    LOCAL_MAPPING_ACTIVE=$(cast call $TOKEN_REGISTRY "isTokenMappingActive(uint32,address,uint32)" 31337 $REGULAR_TOKEN 31337 --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
    
    if [[ $LOCAL_MAPPING_ACTIVE != *"0000000000000000000000000000000000000000000000000000000000000001" ]]; then
        echo "❌ CRITICAL: Local mapping not active for $REGULAR_TOKEN_KEY!"
        echo "   Regular token: $REGULAR_TOKEN"
        echo "   Expected synthetic: $EXPECTED_SYNTHETIC"
        echo "   Local deposits will fail without this mapping"
        echo "   Fix: Run local token configuration script to activate mapping"
        exit 1
    fi
    
    # Get the synthetic token address that TokenRegistry returns for local mapping
    MAPPED_SYNTHETIC=$(cast call $TOKEN_REGISTRY "getSyntheticToken(uint32,address,uint32)" 31337 $REGULAR_TOKEN 31337 --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
    
    # Extract actual address from the 32-byte return value
    if [[ $MAPPED_SYNTHETIC == 0x000000000000000000000000* ]] && [ ${#MAPPED_SYNTHETIC} -eq 66 ]; then
        MAPPED_ADDR="0x${MAPPED_SYNTHETIC:26}"  # Extract last 20 bytes (40 hex chars)
    else
        MAPPED_ADDR="$MAPPED_SYNTHETIC"
    fi
    
    MAPPED_LOWER=$(echo $MAPPED_ADDR | tr '[:upper:]' '[:lower:]')
    EXPECTED_LOWER=$(echo $EXPECTED_SYNTHETIC | tr '[:upper:]' '[:lower:]')
    
    if [ "$MAPPED_LOWER" != "$EXPECTED_LOWER" ]; then
        echo "❌ CRITICAL: TokenRegistry local mapping misconfigured for $REGULAR_TOKEN_KEY!"
        echo "   Regular token: $REGULAR_TOKEN"
        echo "   Expected synthetic: $EXPECTED_SYNTHETIC"
        echo "   TokenRegistry returns: $MAPPED_ADDR"
        echo "   IMPACT: depositLocal() will credit balances under wrong token!"
        echo "   CONSEQUENCE: Users can't trade after making local deposits"
        echo "   Fix: Reconfigure TokenRegistry with correct synthetic token mappings"
        exit 1
    fi
    
    echo "✅ $REGULAR_TOKEN_KEY local mapping validated: $REGULAR_TOKEN -> $MAPPED_ADDR"
done
echo ""

echo "=== Validating ChainBalanceManager Registration ==="
SIDE_CHAINBM=$(jq -r '.ChainBalanceManager' $SIDE_DEPLOYMENT)
CHAIN_ID=31338

REGISTERED_CBM=$(cast call $BALANCE_MANAGER "getChainBalanceManager(uint32)" $CHAIN_ID --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000")

# Extract actual address from the 32-byte return value if needed
if [[ $REGISTERED_CBM == 0x000000000000000000000000* ]] && [ ${#REGISTERED_CBM} -eq 66 ]; then
    REGISTERED_ADDR="0x${REGISTERED_CBM:26}"  # Extract last 20 bytes (40 hex chars)
else
    REGISTERED_ADDR="$REGISTERED_CBM"
fi

REGISTERED_LOWER=$(echo $REGISTERED_ADDR | tr '[:upper:]' '[:lower:]')
EXPECTED_CBM_LOWER=$(echo $SIDE_CHAINBM | tr '[:upper:]' '[:lower:]')

if [ "$REGISTERED_LOWER" != "$EXPECTED_CBM_LOWER" ]; then
    echo "❌ CRITICAL: ChainBalanceManager not registered correctly!"
    echo "   Chain ID: $CHAIN_ID"
    echo "   Expected ChainBalanceManager: $SIDE_CHAINBM"
    echo "   Registered ChainBalanceManager: $REGISTERED_ADDR"
    echo "   Fix: Run 'make configure-cross-chain-tokens network=gtx_core_devnet'"
    exit 1
fi

echo "✅ ChainBalanceManager registration validated: $REGISTERED_ADDR"
echo ""

echo "=== Validating Mailbox Configuration ==="
echo "Checking BalanceManager mailbox configuration..."

# Check BalanceManager mailbox
MAILBOX_CONFIG=$(cast call $BALANCE_MANAGER "getMailboxConfig()" --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

# Check if mailbox is configured (first 32 bytes should not be zero)
ZERO_ADDRESS="0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
if [ "$MAILBOX_CONFIG" = "$ZERO_ADDRESS" ]; then
    echo "❌ CRITICAL: BalanceManager mailbox not configured!"
    echo "   BalanceManager: $BALANCE_MANAGER"
    echo "   Fix: Run 'make configure-cross-chain-tokens network=gtx_core_devnet'"
    exit 1
fi

# Parse mailbox address and domain from the concatenated hex return
# First 32 bytes (64 hex chars after 0x) = address, next 32 bytes = domain
CORE_MAILBOX_FULL=$(echo $MAILBOX_CONFIG | cut -c1-66)  # 0x + 64 chars
CORE_DOMAIN_HEX=$(echo $MAILBOX_CONFIG | cut -c67-130)  # next 64 chars

# Extract actual address from 32-byte format (last 20 bytes)
CORE_MAILBOX_ADDR="0x${CORE_MAILBOX_FULL:26}"

# Convert domain from hex to decimal
CORE_DOMAIN=$((0x$CORE_DOMAIN_HEX))

echo "✅ BalanceManager mailbox validated: $CORE_MAILBOX_ADDR (domain: $CORE_DOMAIN)"

echo "Checking ChainBalanceManager mailbox configuration..."

# Check ChainBalanceManager mailbox
SIDE_MAILBOX_CONFIG=$(cast call $SIDE_CHAINBM "getMailboxConfig()" --rpc-url https://side-devnet.gtxdex.xyz 2>/dev/null || echo "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")

# Check if side chain mailbox is configured
if [ "$SIDE_MAILBOX_CONFIG" = "$ZERO_ADDRESS" ]; then
    echo "❌ CRITICAL: ChainBalanceManager mailbox not configured!"
    echo "   ChainBalanceManager: $SIDE_CHAINBM"
    echo "   Fix: Redeploy side chain with correct mailbox configuration"
    exit 1
fi

# Parse side chain mailbox address and domain from concatenated hex
SIDE_MAILBOX_FULL=$(echo $SIDE_MAILBOX_CONFIG | cut -c1-66)  # 0x + 64 chars
SIDE_DOMAIN_HEX=$(echo $SIDE_MAILBOX_CONFIG | cut -c67-130)  # next 64 chars

# Extract actual address from 32-byte format (last 20 bytes)
SIDE_MAILBOX_ADDR="0x${SIDE_MAILBOX_FULL:26}"

# Convert domain from hex to decimal
SIDE_DOMAIN=$((0x$SIDE_DOMAIN_HEX))

echo "✅ ChainBalanceManager mailbox validated: $SIDE_MAILBOX_ADDR (domain: $SIDE_DOMAIN)"

# Validate that mailboxes have code deployed
echo "Verifying mailbox contracts are deployed..."

CORE_MAILBOX_CODE=$(cast code $CORE_MAILBOX_ADDR --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x")
if [ "$CORE_MAILBOX_CODE" = "0x" ]; then
    echo "❌ CRITICAL: Core mailbox at $CORE_MAILBOX_ADDR has no code!"
    echo "   The mailbox contract is not deployed on the core chain"
    echo "   This will cause all cross-chain messages to fail"
    exit 1
fi

SIDE_MAILBOX_CODE=$(cast code $SIDE_MAILBOX_ADDR --rpc-url https://side-devnet.gtxdex.xyz 2>/dev/null || echo "0x")
if [ "$SIDE_MAILBOX_CODE" = "0x" ]; then
    echo "❌ CRITICAL: Side mailbox at $SIDE_MAILBOX_ADDR has no code!"
    echo "   The mailbox contract is not deployed on the side chain"
    echo "   This will cause all cross-chain messages to fail"
    exit 1
fi

echo "✅ Core mailbox contract verified: $CORE_MAILBOX_ADDR"
echo "✅ Side mailbox contract verified: $SIDE_MAILBOX_ADDR"
echo ""

echo "=== Validating Trading Pools ==="
# Check if PoolManager is deployed and required pools exist
POOL_MANAGER=$(jq -r '.PROXY_POOLMANAGER // .PoolManager' $CORE_DEPLOYMENT 2>/dev/null)
if [ "$POOL_MANAGER" = "null" ] || [ -z "$POOL_MANAGER" ] || [ "$POOL_MANAGER" = "0x0000000000000000000000000000000000000000" ]; then
    echo "⚠️  WARNING: PoolManager not found in core chain deployment"
    echo "   This is optional but required for trading functionality"
    echo "   Pools: gsWETH/gsUSDC, gsWBTC/gsUSDC will not be validated"
else
    POOL_MANAGER_CODE=$(cast code $POOL_MANAGER --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x")
    if [ "$POOL_MANAGER_CODE" = "0x" ]; then
        echo "❌ CRITICAL: PoolManager at $POOL_MANAGER has no code on core chain!"
        echo "   Contract not deployed properly"
        exit 1
    fi
    
    echo "✅ PoolManager validated: $POOL_MANAGER"
    
    # Get synthetic token addresses for pool validation
    GSUSDC=$(jq -r '.gsUSDC' $CORE_DEPLOYMENT)
    GSWETH=$(jq -r '.gsWETH' $CORE_DEPLOYMENT)
    GSWBTC=$(jq -r '.gsWBTC' $CORE_DEPLOYMENT)
    
    # Function to check if pool exists
    check_pool() {
        local TOKEN1=$1
        local TOKEN2=$2
        local POOL_NAME=$3
        
        echo "Checking $POOL_NAME pool ($TOKEN1 / $TOKEN2)..."
        
        # Call poolExists(Currency,Currency) function
        # Both tokens are passed as addresses wrapped in Currency type
        POOL_EXISTS=$(cast call $POOL_MANAGER "poolExists(address,address)" $TOKEN1 $TOKEN2 --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "0x0000000000000000000000000000000000000000000000000000000000000000")
        
        # Extract boolean result from 32-byte return value (last byte)
        if [[ $POOL_EXISTS == *"0000000000000000000000000000000000000000000000000000000000000001" ]]; then
            echo "✅ $POOL_NAME pool exists"
            
            # Try to get liquidity score
            LIQUIDITY_SCORE=$(cast call $POOL_MANAGER "getPoolLiquidityScore(address,address)" $TOKEN1 $TOKEN2 --rpc-url https://core-devnet.gtxdex.xyz 2>/dev/null || echo "unknown")
            if [ "$LIQUIDITY_SCORE" != "unknown" ]; then
                # Convert hex to decimal if it's a valid hex number
                if [[ $LIQUIDITY_SCORE =~ ^0x[0-9a-fA-F]+$ ]]; then
                    LIQUIDITY_DECIMAL=$((LIQUIDITY_SCORE))
                    echo "   Liquidity score: $LIQUIDITY_DECIMAL"
                else
                    echo "   Liquidity score: $LIQUIDITY_SCORE"
                fi
            fi
            return 0
        else
            echo "❌ CRITICAL: $POOL_NAME pool does not exist!"
            echo "   Pool creation required for trading functionality"
            echo "   Token1: $TOKEN1"
            echo "   Token2: $TOKEN2"
            echo "   Fix: Create pool manually or run pool creation script"
            return 1
        fi
    }
    
    # Validate required pools
    POOLS_OK=true
    
    if ! check_pool $GSWETH $GSUSDC "gsWETH/gsUSDC"; then
        POOLS_OK=false
    fi
    
    if ! check_pool $GSWBTC $GSUSDC "gsWBTC/gsUSDC"; then
        POOLS_OK=false
    fi
    
    if [ "$POOLS_OK" = true ]; then
        echo "✅ All required trading pools exist and are ready"
    else
        echo "❌ CRITICAL: Some trading pools are missing!"
        echo "   Trading functionality will not work properly"
        echo "   Create the missing pools before proceeding with trading"
        exit 1
    fi
fi
echo ""

echo "🎉 ALL VALIDATIONS PASSED!"
echo "✅ Core chain contracts deployed and validated"
echo "✅ Side chain contracts deployed and validated"  
echo "✅ All token mappings configured correctly"
echo "✅ BalanceManager configuration verified"
echo "✅ ChainBalanceManager registration verified"
echo "✅ Mailbox configuration verified on both chains"
echo "✅ Trading pools validated (if PoolManager deployed)"
echo "✅ Cross-chain messaging infrastructure ready"
echo "✅ System ready for cross-chain testing"
echo ""
echo "You can now proceed with cross-chain deposit testing:"
echo "   make test-cross-chain-deposit network=gtx_side_devnet"
echo ""
echo "For trading functionality, ensure the following pools exist:"
echo "   • gsWETH/gsUSDC"
echo "   • gsWBTC/gsUSDC"
echo ""
echo "If pools were validated above, trading is ready to use."
echo "If PoolManager was not found, pools will need to be created separately."
echo ""
echo "Validation completed at: $(date)"