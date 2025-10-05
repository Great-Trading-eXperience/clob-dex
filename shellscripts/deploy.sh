#!/bin/bash

# GTX Two-Chain Trading System - Automated Deployment Script
# Automates deployment from Step 0 (Clean Previous Data) to Validation

set -e  # Exit on any error

# Set timeout for long-running operations (20 minutes)
export FORGE_TIMEOUT=1200

echo "🚀 Starting GTX Two-Chain Trading System Deployment..."

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

# Check for required environment variables
if [[ -z "$CORE_MAILBOX" ]] || [[ -z "$SIDE_MAILBOX" ]]; then
    print_error "Required environment variables not set!"
    echo "Please set CORE_MAILBOX and SIDE_MAILBOX first:"
    echo ""
    echo "# Extract mailbox addresses from Hyperlane deployment"
    echo "export CORE_MAILBOX=\$(grep 'mailbox:' \$PROJECT_DIR/hyperlane/chains/gtx-core-devnet/addresses.yaml | awk '{print \$2}' | tr -d '\"')"
    echo "export SIDE_MAILBOX=\$(grep 'mailbox:' \$PROJECT_DIR/hyperlane/chains/gtx-side-devnet/addresses.yaml | awk '{print \$2}' | tr -d '\"')"
    echo ""
    echo "# Verify extraction worked"
    echo "echo \"CORE_MAILBOX: \$CORE_MAILBOX\""
    echo "echo \"SIDE_MAILBOX: \$SIDE_MAILBOX\""
    exit 1
fi

print_success "Environment variables verified:"
echo "  CORE_MAILBOX: $CORE_MAILBOX"
echo "  SIDE_MAILBOX: $SIDE_MAILBOX"
echo ""

# Step 0: Clean Previous Data
print_step "Step 0: Cleaning previous deployment data..."
rm -f deployments/*.json
rm -rf broadcast/ cache/ out/
print_success "Previous data cleaned"

# Step 1: Deploy Core Chain Trading
print_step "Step 1: Deploying Core Chain Trading..."
CORE_MAILBOX=$CORE_MAILBOX SIDE_MAILBOX=$SIDE_MAILBOX make deploy-core-chain-trading network=gtx_core_devnet
print_success "Core Chain Trading deployed"

# Step 2: Deploy Side Chain Tokens
print_step "Step 2: Deploying Side Chain Tokens..."
make deploy-side-chain-tokens network=gtx_side_devnet
print_success "Side Chain Tokens deployed"

# Step 3: Deploy Core Chain Tokens
print_step "Step 3: Deploying Core Chain Tokens..."
make deploy-core-chain-tokens network=gtx_core_devnet
print_success "Core Chain Tokens deployed"

# Step 4: Create Trading Pools
print_step "Step 4: Creating Trading Pools..."
make create-trading-pools network=gtx_core_devnet
print_success "Trading Pools created"

# Step 5: Deploy Side Chain Balance Manager
print_step "Step 5: Deploying Side Chain Balance Manager..."
SIDE_MAILBOX=$SIDE_MAILBOX CORE_MAILBOX=$CORE_MAILBOX make deploy-side-chain-bm network=gtx_side_devnet
print_success "Side Chain Balance Manager deployed"

# Step 6: Configure Cross-Chain
print_step "Step 6: Configuring Cross-Chain..."
make register-side-chain network=gtx_core_devnet
make configure-balance-manager network=gtx_core_devnet
make update-core-chain-mappings network=gtx_core_devnet
print_success "Cross-Chain configuration completed"

# Step 7: Update Side Chain Mappings
print_step "Step 7: Updating Side Chain Mappings..."
make update-side-chain-mappings network=gtx_side_devnet
print_success "Side Chain Mappings updated"

echo ""
print_success "🎉 Deployment completed successfully!"

# Validation
print_step "Validating Core Deployment..."
if make validate-deployment; then
    print_success "Core deployment validation passed!"
else
    print_error "Core deployment validation failed!"
    exit 1
fi

echo ""
print_success "🌟 GTX Two-Chain Trading System is ready!"

# Check if deployment files exist
if [[ -f "deployments/31337.json" ]] && [[ -f "deployments/31338.json" ]]; then
    print_success "✅ Deployment files created successfully:"
    echo "  📁 deployments/31337.json - Core chain contracts"
    echo "  📁 deployments/31338.json - Side chain contracts"
else
    print_warning "⚠️  Some deployment files may be missing. Check for errors above."
fi

echo ""
echo "Next steps (optional):"
echo "  🔍 Validate cross-chain system: make validate-cross-chain-deposit"
echo "  🧪 Test cross-chain deposits: make test-cross-chain-deposit network=gtx_side_devnet side_chain=31338 core_chain=31337 token=USDC amount=1000000000"
echo "  🧪 Test local deposits: make test-local-deposit network=gtx_core_devnet token=USDC amount=1000000000"
echo "  📊 Populate trading data: make validate-data-population"

echo ""
print_success "🎯 Deployment completed in $(date)"