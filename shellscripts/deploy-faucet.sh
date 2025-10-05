#!/bin/bash

# GTX Faucet System - Automated Deployment Script
# Automates the complete faucet deployment and setup

set -e  # Exit on any error

echo "🚀 Starting GTX Faucet System Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Default network (can be overridden by passing as argument)
NETWORK=${1:-gtx_side_devnet}

echo "🎯 Target Network: $NETWORK"
echo ""

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Check for required environment variables
if [[ -z "$PRIVATE_KEY" ]]; then
    print_warning "PRIVATE_KEY not set. Using default Anvil account..."
    export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
fi

print_success "Environment configured:"
echo "  Deployer: $(cast wallet address --private-key $PRIVATE_KEY)"
echo "  Network: $NETWORK"
echo ""

# Get RPC URL based on network
case $NETWORK in
    gtx_core_devnet)
        RPC_URL="https://core-devnet.gtxdex.xyz"
        CHAIN_NAME="GTX Core Chain"
        ;;
    gtx_side_devnet)
        RPC_URL="https://side-devnet.gtxdex.xyz"
        CHAIN_NAME="GTX Side Chain"
        ;;
    rari_testnet)
        RPC_URL="https://rari.caff.testnet.espresso.network"
        CHAIN_NAME="Rari Testnet"
        ;;
    appchain_testnet)
        RPC_URL="https://appchain.caff.testnet.espresso.network"
        CHAIN_NAME="Appchain Testnet"
        ;;
    *)
        print_warning "Unknown network: $NETWORK. Proceeding with provided network name..."
        RPC_URL="https://side-devnet.gtxdex.xyz"  # Default fallback
        CHAIN_NAME="Unknown Network"
        ;;
esac

print_success "Network details:"
echo "  Chain: $CHAIN_NAME"
echo "  RPC: $RPC_URL"
echo ""

print_success "🎯 Starting Complete Faucet Deployment Flow..."

# Step 1: Deploy Faucet Contract
print_step "Step 1: Deploying Faucet Contract (Beacon + Proxy)..."
if make deploy-faucet network=$NETWORK; then
    print_success "Faucet contracts deployed successfully"
else
    print_error "Faucet deployment failed!"
    exit 1
fi

# Step 2: Configure Faucet Settings
print_step "Step 2: Configuring Faucet Settings..."
if make setup-faucet network=$NETWORK; then
    print_success "Faucet settings configured (Amount: 1M tokens, Cooldown: 1s)"
else
    print_error "Faucet configuration failed!"
    exit 1
fi

# Step 3: Add Tokens to Faucet
print_step "Step 3: Adding Mock Tokens to Faucet..."
if make add-faucet-tokens network=$NETWORK; then
    print_success "Mock tokens added (WETH: 1000, USDC: 2M)"
else
    print_error "Token addition failed!"
    exit 1
fi

# Step 4: Deposit Additional Tokens (Optional)
print_step "Step 4: Depositing Additional Tokens..."
if make deposit-faucet-tokens network=$NETWORK; then
    print_success "Additional tokens deposited to faucet"
else
    print_warning "Additional token deposit failed (this is optional)"
fi

echo ""
print_success "🎉 Faucet Deployment completed successfully!"

# Verification
print_step "Verifying Faucet Deployment..."

# Get deployment file path
CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL 2>/dev/null || echo "unknown")
DEPLOYMENT_FILE="deployments/${CHAIN_ID}.json"

if [[ -f "$DEPLOYMENT_FILE" ]]; then
    print_success "Deployment file found: $DEPLOYMENT_FILE"
    
    # Extract addresses
    if command -v jq > /dev/null 2>&1; then
        FAUCET_PROXY=$(jq -r '.PROXY_FAUCET // empty' "$DEPLOYMENT_FILE")
        FAUCET_BEACON=$(jq -r '.BEACON_FAUCET // empty' "$DEPLOYMENT_FILE")
        WETH_TOKEN=$(jq -r '.MOCK_TOKEN_WETH // empty' "$DEPLOYMENT_FILE")
        USDC_TOKEN=$(jq -r '.MOCK_TOKEN_USDC // empty' "$DEPLOYMENT_FILE")
        
        if [[ -n "$FAUCET_PROXY" && "$FAUCET_PROXY" != "null" ]]; then
            print_success "✅ Faucet Proxy: $FAUCET_PROXY"
            
            # Test faucet configuration
            echo "  🔍 Verifying faucet configuration..."
            FAUCET_AMOUNT=$(cast call $FAUCET_PROXY "getFaucetAmount()" --rpc-url $RPC_URL 2>/dev/null || echo "failed")
            COOLDOWN=$(cast call $FAUCET_PROXY "getCooldown()" --rpc-url $RPC_URL 2>/dev/null || echo "failed")
            TOKEN_COUNT=$(cast call $FAUCET_PROXY "getAvailableTokensLength()" --rpc-url $RPC_URL 2>/dev/null || echo "failed")
            
            if [[ "$FAUCET_AMOUNT" != "failed" ]]; then
                echo "    💰 Faucet Amount: $FAUCET_AMOUNT"
            fi
            if [[ "$COOLDOWN" != "failed" ]]; then
                echo "    ⏰ Cooldown: $COOLDOWN seconds"
            fi
            if [[ "$TOKEN_COUNT" != "failed" ]]; then
                echo "    🪙 Available Tokens: $TOKEN_COUNT"
            fi
        fi
        
        if [[ -n "$FAUCET_BEACON" && "$FAUCET_BEACON" != "null" ]]; then
            print_success "✅ Faucet Beacon: $FAUCET_BEACON"
        fi
        
        if [[ -n "$WETH_TOKEN" && "$WETH_TOKEN" != "null" ]]; then
            print_success "✅ WETH Token: $WETH_TOKEN"
        fi
        
        if [[ -n "$USDC_TOKEN" && "$USDC_TOKEN" != "null" ]]; then
            print_success "✅ USDC Token: $USDC_TOKEN"
        fi
    else
        print_warning "jq not installed. Deployment file exists but cannot parse addresses."
    fi
else
    print_warning "Deployment file not found. Contracts may be deployed but addresses not saved."
fi

echo ""
print_success "🌟 GTX Faucet System is ready!"

echo ""
echo "📋 Deployment Summary:"
echo "  🌍 Network: $CHAIN_NAME ($NETWORK)"
echo "  🔗 Chain ID: $CHAIN_ID"
echo "  📄 Config: $DEPLOYMENT_FILE"
echo ""

if [[ -n "$FAUCET_PROXY" && "$FAUCET_PROXY" != "null" ]]; then
    echo "🧪 Test the faucet:"
    echo "  # Request WETH tokens"
    echo "  cast send $FAUCET_PROXY \"requestTokens(address)\" $WETH_TOKEN \\"
    echo "    --private-key \$PRIVATE_KEY --rpc-url $RPC_URL"
    echo ""
    echo "  # Request USDC tokens"
    echo "  cast send $FAUCET_PROXY \"requestTokens(address)\" $USDC_TOKEN \\"
    echo "    --private-key \$PRIVATE_KEY --rpc-url $RPC_URL"
    echo ""
fi

echo "🔗 Integration with GTX System:"
echo "  1. Deploy main GTX system: ./deploy.sh"
echo "  2. Use faucet tokens for cross-chain deposits"
echo "  3. Trade with faucet-distributed tokens"
echo ""

print_success "🎯 Faucet deployment completed in $(date)"