#!/bin/bash

# GTX Trading System - Data Population Automation Script
# Populates the system with test traders and trading activity

set -e  # Exit on any error

echo "🚀 Starting GTX Trading System Data Population..."

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

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

# Load environment variables from .env file if it exists
if [[ -f ".env" ]]; then
    print_step "Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a  # turn off auto-export
    print_success "Environment variables loaded from .env"
fi

# Set trader accounts
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export PRIVATE_KEY_2=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d

print_success "Trader accounts configured:"
echo "  Primary Trader: $(cast wallet address --private-key $PRIVATE_KEY)"
echo "  Secondary Trader: $(cast wallet address --private-key $PRIVATE_KEY_2)"
echo ""

# Prerequisites - Validate deployment
print_step "Prerequisites: Validating deployment..."
if make validate-deployment > /dev/null 2>&1; then
    print_success "Deployment validation passed"
else
    print_error "Deployment validation failed! Please run ./deploy.sh first"
    exit 1
fi

echo ""
print_success "🎯 Starting Complete Trading Flow..."

# Step 1: Primary trader deposits tokens
print_step "Step 1: Primary trader deposits tokens..."
echo "  💰 Depositing USDC (1000 USDC)..."
PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=1000000000 make test-local-deposit network=gtx_core_devnet
print_success "USDC deposit completed"

echo "  💰 Depositing WETH (10 WETH)..."
PRIVATE_KEY=$PRIVATE_KEY TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=10000000000000000000 make test-local-deposit network=gtx_core_devnet
print_success "WETH deposit completed"

# Step 2: Transfer tokens to secondary trader
print_step "Step 2: Transferring tokens to secondary trader..."
echo "  🔄 Transferring USDC (5000 USDC)..."
make transfer-tokens network=gtx_core_devnet recipient=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 token=USDC amount=5000000000
print_success "USDC transfer completed"

echo "  🔄 Transferring WETH (5 WETH)..."
make transfer-tokens network=gtx_core_devnet recipient=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 token=WETH amount=5000000000000000000
print_success "WETH transfer completed"

# Step 3: Secondary trader deposits tokens
print_step "Step 3: Secondary trader deposits tokens..."
echo "  💰 Secondary trader depositing USDC (2000 USDC)..."
PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=USDC DEPOSIT_AMOUNT=2000000000 TEST_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 make test-local-deposit network=gtx_core_devnet
print_success "Secondary trader USDC deposit completed"

echo "  💰 Secondary trader depositing WETH (2 WETH)..."
PRIVATE_KEY=$PRIVATE_KEY_2 TOKEN_SYMBOL=WETH DEPOSIT_AMOUNT=2000000000000000000 TEST_RECIPIENT=0x70997970C51812dc3A010C7d01b50e0d17dc79C8 make test-local-deposit network=gtx_core_devnet
print_success "Secondary trader WETH deposit completed"

# Step 4: Primary trader creates liquidity
print_step "Step 4: Primary trader creating liquidity (limit orders)..."
PRIVATE_KEY=$PRIVATE_KEY make fill-orderbook network=gtx_core_devnet
print_success "Orderbook liquidity created"

# Step 5: Secondary trader executes trades
print_step "Step 5: Secondary trader executing market orders..."
if PRIVATE_KEY=$PRIVATE_KEY_2 make market-order network=gtx_core_devnet; then
    print_success "Market orders executed successfully"
else
    print_warning "Market order failed, trying alternative approach..."
    if PRIVATE_KEY=$PRIVATE_KEY_2 make fill-orderbook network=gtx_core_devnet; then
        print_success "Alternative trading strategy executed"
    else
        print_error "Both trading strategies failed. Check logs for details."
        echo ""
        echo "Debug commands:"
        echo "  make diagnose-market-order network=gtx_core_devnet"
        echo "  make validate-data-population"
        exit 1
    fi
fi

echo ""
print_success "🎉 Data Population completed successfully!"

# Validation
print_step "Validating data population..."
if make validate-data-population; then
    print_success "Data population validation passed!"
    echo ""
    echo "✅ System now contains:"
    echo "  📊 Two active traders with synthetic token balances"
    echo "  📈 OrderBook with liquidity (limit orders)"
    echo "  🔄 Trading activity (market orders executed)"
    echo "  💹 Live trading environment ready"
else
    print_warning "Data population validation had issues. Check logs above."
    echo ""
    echo "Debug commands:"
    echo "  make diagnose-market-order network=gtx_core_devnet"
    echo "  cast balance \$(cast wallet address --private-key \$PRIVATE_KEY) --rpc-url https://core-devnet.gtxdex.xyz"
    echo "  cast balance \$(cast wallet address --private-key \$PRIVATE_KEY_2) --rpc-url https://core-devnet.gtxdex.xyz"
fi

echo ""
print_success "🌟 GTX Trading System is populated and ready for use!"
echo ""
echo "Next steps:"
echo "  🤖 Start trading bots: cd /Users/renaka/gtx/barista-bot-2 && npm run dev"
echo "  📊 Start indexer: cd /Users/renaka/gtx/clob-indexer && npm run dev"
echo "  🌐 Access frontend: https://gtxdex.xyz"
echo ""
print_success "🎯 Data population completed in $(date)"