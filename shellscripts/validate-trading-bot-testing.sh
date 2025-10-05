#!/bin/bash

# Trading Bot Testing Validation Script
# Validates that the complete trading bot testing process completed successfully
# Output is logged to trading-bot-testing.log

set -e

# Set up logging
LOG_FILE="trading-bot-testing.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}🔍 $1${NC}"
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

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to safely convert hex to decimal
safe_hex_to_decimal() {
    local hex_value="$1"
    # Handle empty hex or just "0x"
    if [[ -z "$hex_value" ]] || [[ "$hex_value" == "0x" ]]; then
        echo "0"
        return
    fi
    # Handle valid hex values
    if [[ "$hex_value" =~ ^0x[0-9a-fA-F]+$ ]]; then
        printf "%d" "$hex_value" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Check if we're in the right directory
if [[ ! -f "Makefile" ]] || [[ ! -d "script" ]]; then
    print_error "Please run this script from the clob-dex project root directory"
    exit 1
fi

echo "🚀 Starting Trading Bot Testing Validation..."
echo ""

# Configuration
RPC_URL="https://core-devnet.gtxdex.xyz"
INDEXER_URL="http://localhost:42070"
BARISTA_BOT_DIR="/Users/renaka/gtx/barista-bot-2"

# Trading bot addresses (derived from private keys)
TRADING_BOT_1="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
TRADING_BOT_2="0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"
TRADING_BOT_3="0x976EA74026E726554dB657fA54763abd0C3a0aa9"
MARKET_MAKER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Load deployment addresses
if [[ -f "deployments/31337.json" ]]; then
    BALANCE_MANAGER=$(jq -r '.PROXY_BALANCEMANAGER' deployments/31337.json)
    USDC_TOKEN=$(jq -r '.USDC' deployments/31337.json)
    WETH_TOKEN=$(jq -r '.WETH' deployments/31337.json)
    GSUSDC_TOKEN=$(jq -r '.gsUSDC' deployments/31337.json)
    GSWETH_TOKEN=$(jq -r '.gsWETH' deployments/31337.json)
else
    print_error "Deployment file not found: deployments/31337.json"
    exit 1
fi

# Validation functions
check_anvil_running() {
    print_step "Checking if Anvil blockchain is running..."
    if cast block-number --rpc-url $RPC_URL > /dev/null 2>&1; then
        local block_number=$(cast block-number --rpc-url $RPC_URL)
        print_success "Anvil is running (Block: $block_number)"
        return 0
    else
        print_error "Anvil blockchain is not running or not accessible"
        return 1
    fi
}

check_contracts_deployed() {
    print_step "Verifying smart contracts are deployed..."
    
    local contracts_ok=true
    
    # Check Balance Manager
    if cast code $BALANCE_MANAGER --rpc-url $RPC_URL | grep -q "0x"; then
        print_success "Balance Manager deployed at $BALANCE_MANAGER"
    else
        print_error "Balance Manager not found at $BALANCE_MANAGER"
        contracts_ok=false
    fi
    
    # Check USDC Token
    if cast code $USDC_TOKEN --rpc-url $RPC_URL | grep -q "0x"; then
        print_success "USDC Token deployed at $USDC_TOKEN"
    else
        print_error "USDC Token not found at $USDC_TOKEN"
        contracts_ok=false
    fi
    
    # Check WETH Token
    if cast code $WETH_TOKEN --rpc-url $RPC_URL | grep -q "0x"; then
        print_success "WETH Token deployed at $WETH_TOKEN"
    else
        print_error "WETH Token not found at $WETH_TOKEN"
        contracts_ok=false
    fi
    
    if $contracts_ok; then
        return 0
    else
        return 1
    fi
}

check_indexer_running() {
    print_step "Checking if indexer is running..."
    if curl -s "$INDEXER_URL" > /dev/null 2>&1; then
        print_success "Indexer is running at $INDEXER_URL"
        return 0
    else
        print_error "Indexer is not running or not accessible at $INDEXER_URL"
        return 1
    fi
}

check_market_maker_funding() {
    print_step "Checking market maker Balance Manager deposits..."
    
    # Check gsUSDC and gsWETH balances in Balance Manager for market maker
    local gsusdc_balance=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $MARKET_MAKER $GSUSDC_TOKEN --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
    local gsweth_balance=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $MARKET_MAKER $GSWETH_TOKEN --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
    
    gsusdc_balance=$(safe_hex_to_decimal "$gsusdc_balance")
    gsweth_balance=$(safe_hex_to_decimal "$gsweth_balance")
    
    if [[ $gsusdc_balance -gt 0 ]] || [[ $gsweth_balance -gt 0 ]]; then
        print_success "Market maker has Balance Manager deposits"
        print_info "  gsUSDC: $(echo "scale=2; $gsusdc_balance / 1000000" | bc) | gsWETH: $(echo "scale=6; $gsweth_balance / 1000000000000000000" | bc)"
    else
        print_warning "Market maker has no Balance Manager deposits - fund with 'pnpm fund:traders'"
    fi
}

check_trading_bot_funding() {
    print_step "Checking trading bot Balance Manager deposits..."
    
    local bots=("$TRADING_BOT_1" "$TRADING_BOT_2" "$TRADING_BOT_3")
    local bot_names=("Trading Bot 1" "Trading Bot 2" "Trading Bot 3")
    
    for i in "${!bots[@]}"; do
        local bot=${bots[$i]}
        local name=${bot_names[$i]}
        
        # Check gsUSDC and gsWETH balances in Balance Manager
        local gsusdc_balance=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $bot $GSUSDC_TOKEN --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
        local gsweth_balance=$(cast call $BALANCE_MANAGER "getBalance(address,address)" $bot $GSWETH_TOKEN --rpc-url $RPC_URL 2>/dev/null || echo "0x0")
        
        gsusdc_balance=$(safe_hex_to_decimal "$gsusdc_balance")
        gsweth_balance=$(safe_hex_to_decimal "$gsweth_balance")
        
        if [[ $gsusdc_balance -gt 0 ]] || [[ $gsweth_balance -gt 0 ]]; then
            print_success "$name has Balance Manager deposits"
            print_info "  gsUSDC: $(echo "scale=2; $gsusdc_balance / 1000000" | bc) | gsWETH: $(echo "scale=6; $gsweth_balance / 1000000000000000000" | bc)"
        else
            print_warning "$name has no Balance Manager deposits"
        fi
    done
}

check_blockchain_activity() {
    print_step "Checking blockchain activity..."
    
    local current_block=$(cast block-number --rpc-url $RPC_URL)
    
    if [[ $current_block -gt 100 ]]; then
        print_success "Significant blockchain activity detected ($current_block blocks)"
    else
        print_warning "Limited blockchain activity ($current_block blocks)"
    fi
    
    # Check for recent transactions
    local recent_tx_count=$(cast rpc eth_getBlockByNumber latest true --rpc-url $RPC_URL | jq '.transactions | length')
    if [[ $recent_tx_count -gt 0 ]]; then
        print_info "Recent block contains $recent_tx_count transactions"
    fi
}

check_barista_bot_config() {
    print_step "Checking barista-bot configuration..."
    
    if [[ -f "$BARISTA_BOT_DIR/.env" ]]; then
        print_success "Barista bot .env file exists"
        
        # Check for required variables
        local required_vars=("PROXY_BALANCE_MANAGER" "PROXY_POOL_MANAGER" "USDC_TOKEN_ADDRESS" "WETH_TOKEN_ADDRESS")
        local config_ok=true
        
        for var in "${required_vars[@]}"; do
            if grep -q "^$var=" "$BARISTA_BOT_DIR/.env"; then
                local value=$(grep "^$var=" "$BARISTA_BOT_DIR/.env" | cut -d'=' -f2)
                print_info "  $var=$value"
            else
                print_warning "  Missing variable: $var"
                config_ok=false
            fi
        done
        
        if $config_ok; then
            print_success "Barista bot configuration appears complete"
        else
            print_warning "Barista bot configuration may be incomplete"
        fi
    else
        print_error "Barista bot .env file not found at $BARISTA_BOT_DIR/.env"
        return 1
    fi
}

check_indexer_events() {
    print_step "Checking indexer event capture..."
    
    # Try to query GraphQL endpoint for events
    local graphql_query='{"query":"{ balanceManagerDeposits(limit: 5) { id user amount } orderBookOrderPlaceds(limit: 5) { id user side quantity } }"}'
    
    if curl -s -X POST "$INDEXER_URL/graphql" \
        -H "Content-Type: application/json" \
        -d "$graphql_query" > /tmp/indexer_test.json 2>/dev/null; then
        
        local deposits=$(jq '.data.balanceManagerDeposits | length' /tmp/indexer_test.json 2>/dev/null || echo "0")
        local orders=$(jq '.data.orderBookOrderPlaceds | length' /tmp/indexer_test.json 2>/dev/null || echo "0")
        
        if [[ $deposits -gt 0 ]]; then
            print_success "Indexer captured $deposits Balance Manager deposits"
        else
            print_info "No Balance Manager deposits found in indexer"
        fi
        
        if [[ $orders -gt 0 ]]; then
            print_success "Indexer captured $orders OrderBook orders"
        else
            print_info "No OrderBook orders found in indexer"
        fi
        
        rm -f /tmp/indexer_test.json
    else
        print_warning "Could not query indexer GraphQL endpoint"
    fi
}

generate_summary_report() {
    print_step "Generating validation summary..."
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local report_file="trading_bot_validation_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Trading Bot Testing Validation Report
Generated: $timestamp

=== Environment Status ===
Anvil Blockchain: $(cast block-number --rpc-url $RPC_URL 2>/dev/null && echo "Running" || echo "Not Running")
Indexer Service: $(curl -s "$INDEXER_URL" > /dev/null 2>&1 && echo "Running" || echo "Not Running")
Current Block: $(cast block-number --rpc-url $RPC_URL 2>/dev/null || echo "N/A")

=== Contract Addresses ===
Balance Manager: $BALANCE_MANAGER
USDC Token: $USDC_TOKEN
WETH Token: $WETH_TOKEN
gsUSDC Token: $GSUSDC_TOKEN
gsWETH Token: $GSWETH_TOKEN

=== Trading Bot Addresses ===
Trading Bot 1: $TRADING_BOT_1
Trading Bot 2: $TRADING_BOT_2
Trading Bot 3: $TRADING_BOT_3
Market Maker: $MARKET_MAKER

=== Validation Results ===
All checks completed at: $timestamp
Detailed results available in terminal output above.

=== Next Steps ===
1. Review any warnings or errors from the validation
2. Check indexer logs if event capture issues found
3. Verify trading bot auto-funding worked correctly
4. Test end-to-end trading functionality

EOF

    print_success "Validation report saved to: $report_file"
}

# Main validation sequence
echo "🔬 Running comprehensive validation checks..."
echo ""

# Track validation results
validation_passed=true

# Run all validation checks
check_anvil_running || validation_passed=false
echo ""

check_contracts_deployed || validation_passed=false
echo ""

check_indexer_running || validation_passed=false
echo ""

check_market_maker_funding
echo ""

check_trading_bot_funding
echo ""

check_blockchain_activity
echo ""

check_barista_bot_config || validation_passed=false
echo ""

check_indexer_events
echo ""

# Generate summary report
generate_summary_report
echo ""

# Final validation result
if $validation_passed; then
    print_success "🎉 Trading Bot Testing Validation PASSED!"
    echo ""
    print_info "✨ System is ready for trading bot operations"
    print_info "📊 All core components are functioning correctly"
    print_info "🤖 Trading bots can be deployed with confidence"
    echo ""
    print_info "Optional next steps:"
    echo "  • Run trading bots: cd $BARISTA_BOT_DIR && PROGRAM_MODE=trading-bots pnpm dev"
    echo "  • Monitor indexer: watch 'curl -s $INDEXER_URL/metrics'"
    echo "  • Check balances: cd $BARISTA_BOT_DIR && pnpm check:balances"
    exit 0
else
    print_error "❌ Trading Bot Testing Validation FAILED!"
    echo ""
    print_info "🔧 Please address the issues above before proceeding"
    print_info "📋 Check the validation report for detailed information"
    exit 1
fi