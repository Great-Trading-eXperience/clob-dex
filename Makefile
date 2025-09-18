-include .env

# Default values
# DEFAULT_NETWORK := arbitrumSepolia
DEFAULT_NETWORK := default_network
FORK_NETWORK := mainnet

# Custom flag can be set via make flag=<flag> e.g. make flag="-vvvv --force"
flag ?=

# Custom network can be set via make network=<network_name>
network ?= $(DEFAULT_NETWORK)

# =============================================================
#                   ESPRESSO HYPERLANE INTEGRATION
# =============================================================

# Espresso testnet RPC URLs (proven working)
RARI_RPC := https://rari.caff.testnet.espresso.network
APPCHAIN_RPC := https://appchain.caff.testnet.espresso.network
ARBITRUM_RPC := https://sepolia-rollup.arbitrum.io/rpc
GTX_ANVIL_RPC := https://anvil.gtxdex.xyz
GTX_ANVIL_2_RPC := https://side-anvil.gtxdex.xyz

# Helper function to get RPC URL by network name
define get_rpc_url
$(if $(filter rari_testnet,$(1)),$(RARI_RPC),\
$(if $(filter appchain_testnet,$(1)),$(APPCHAIN_RPC),\
$(if $(filter arbitrum_sepolia,$(1)),$(ARBITRUM_RPC),\
$(if $(filter gtx_anvil,$(1)),$(GTX_ANVIL_RPC),\
$(if $(filter gtx_anvil_2,$(1)),$(GTX_ANVIL_2_RPC),\
$(1))))))
endef

# Helper function to get chain name for deployment files (using chain IDs)
define get_chain_name
$(if $(filter rari_testnet,$(1)),rari,$(if $(filter appchain_testnet,$(1)),appchain,$(if $(filter arbitrum_sepolia,$(1)),arbitrum-sepolia,$(if $(filter gtx_anvil,$(1)),31337,$(if $(filter gtx_anvil_2,$(1)),31338,$(1))))))
endef

# Helper function to get paired chain ID (for cross-chain operations)
define get_paired_chain
$(if $(filter gtx_anvil,$(1)),31338,$(if $(filter gtx_anvil_2,$(1)),31337,$(1)))
endef

.PHONY: account chain compile deploy deploy-verify flatten fork format generate lint test verify upgrade upgrade-verify full-integration simple-integration simple-demo swap deploy-chain-balance-manager add-tokens-chain-balance-manager add-single-token-chain-balance-manager remove-single-token-chain-balance-manager list-tokens-chain-balance-manager test-chain-balance-manager fill-orderbook-tokens market-orderbook-tokens deploy-upgradeable-gtx upgrade-gtx-contract test-espresso-integration check-env verify-balance validate-deployment validate-data-population validate-cross-chain-deposit test-local-deposit fill-orderbook fill-orderbook-custom market-order transfer-tokens diagnose-market-order

# Helper function to run forge script
define forge_script
	forge script script/Deploy.s.sol:Deploy --rpc-url $(network) --broadcast $(flag)
endef

# Helper function to run upgrade script
define forge_upgrade_script
 forge script script/maintenance/UpgradeBeaconProxies.s.sol:UpgradeBeaconProxies --rpc-url $(network) --broadcast $(flag)
endef

# Helper function to run mock deployment script
define forge_deploy_mocks
	forge script script/DeployMocks.s.sol:DeployMocks --rpc-url $(network) --broadcast $(flag)
endef







define forge_swap
	forge script script/trading/Swap.s.sol:Swap --rpc-url $(network) --broadcast $(flag)
endef


define forge_deploy_faucet
	forge script script/faucet/DeployFaucet.s.sol:DeployFaucet --rpc-url $(network) --broadcast $(flag)
endef

define forge_setup_faucet
	forge script script/faucet/SetupFaucet.s.sol:SetupFaucet --rpc-url $(network) --broadcast $(flag)
endef

define forge_add_faucet_tokens
	forge script script/faucet/AddToken.s.sol:AddToken --rpc-url $(network) --broadcast $(flag)
endef

define forge_deposit_faucet_tokens
	forge script script/faucet/DepositToken.s.sol:DepositToken --rpc-url $(network) --broadcast $(flag)
endef

# Environment check
check-env:
	@if [ -z "$(PRIVATE_KEY)" ]; then \
		echo "Error: PRIVATE_KEY not set in .env"; \
		exit 1; \
	fi

# Define a target to deploy using the specified network
deploy:
	$(call forge_script,)
	$(MAKE) generate-abi

# Define a target to verify deployment using the specified network
deploy-verify:
	$(call forge_script,--verify)
	$(MAKE) generate-abi

# Define a target to upgrade contracts using the specified network
upgrade:
	 $(call forge_upgrade_script,)
	 $(MAKE) generate-abi

# Define a target to upgrade and verify contracts using the specified network
upgrade-verify:
	 $(call forge_upgrade_script,--verify)
	 $(MAKE) generate-abi

# Define a target to deploy mock contracts
deploy-mocks:
	$(call forge_deploy_mocks,)

# Define a target to deploy and verify mock contracts
deploy-mocks-verify:
	$(call forge_deploy_mocks,--verify)

# Define a target to execute swaps
swap:
	$(call forge_swap,)

# Test ChainBalanceManager
test-chain-balance-manager:
	forge test --match-contract ChainBalanceManagerTest -v

# Send tokens with balance logging
send-token:
	$(call forge_send_token,)

# Define a target to deploy faucet
deploy-faucet:
	$(call forge_deploy_faucet,)

# Define a target to deploy and verify faucet
deploy-faucet-verify:
	$(call forge_deploy_faucet,--verify)

# Define a target to setup faucet
setup-faucet:
	$(call forge_setup_faucet,)

# Define a target to add tokens to faucet
add-faucet-tokens:
	$(call forge_add_faucet_tokens,)

# Define a target to deposit tokens to faucet
deposit-faucet-tokens:
	$(call forge_deposit_faucet_tokens,)

# Define a target to check token balances
check-balances:
	$(call forge_check_balances,)

# Define a target to run simple integration (deploy, deploy-mocks, simple demo)
simple-integration:
	@echo "=========================================="
	@echo "Starting Simple Integration Demo..."
	@echo "=========================================="
	@echo "Step 1: Deploying core contracts..."
	$(MAKE) deploy
	@echo "\n✓ Core contracts deployed"
	@sleep 2
	@echo "\nStep 2: Deploying mock tokens..."
	$(MAKE) deploy-mocks
	@echo "\n✓ Mock tokens deployed"
	@sleep 2
	@echo "\nStep 3: Running simple market order demo..."
	$(MAKE) simple-demo
	@echo "\n✓ Simple market order demo completed"
	@echo "\n=========================================="
	@echo "Simple Integration Demo Complete!"
	@echo "=========================================="

# Define a target to run full integration (deploy everything and test)
full-integration:
	@echo "=========================================="
	@echo "Starting Full Integration Test Sequence..."
	@echo "=========================================="
	@echo "Step 1: Deploying core contracts..."
	$(MAKE) deploy
	@echo "\n✓ Core contracts deployed"
	@sleep 2
	@echo "Step 2: Deploying mock tokens..."
	$(MAKE) deploy-mocks
	@echo "\n✓ Mock tokens deployed"
	@sleep 2
	@echo "\nStep 3: Deploying and setting up faucet..."
	forge clean
	$(MAKE) deploy-faucet
	$(MAKE) setup-faucet
	$(MAKE) add-faucet-tokens
	$(MAKE) deposit-faucet-tokens
	@echo "\n✓ Faucet deployed and configured"
	@sleep 2
	@echo "Step 4: Filling orderbook with limit orders..."
	$(MAKE) fill-orderbook
	@echo "\n✓ Orderbook filled with limit orders"
	@sleep 2
	@echo "Step 5: Placing market orders..."
	$(MAKE) market-orderbook
	@echo "\n✓ Market orders placed and executed"
	@sleep 2
	@echo "Step 6: Executing swaps..."
	$(MAKE) swap
	@echo "\n✓ Swaps executed"
	@sleep 2
	@echo "\n=========================================="
	@echo "Full Integration Test Complete!"
	@echo "=========================================="

compile-watch-core:
	forge build src/core --watch src/core

test-core:
	forge test src/core --watch src/core

# Define a target to compile the contracts
compile:
	forge compile

# Define a target to run tests
test:
	forge test

# Define a target to lint the code
lint:
	forge fmt

# Define a target to generate ABI files
generate-abi:
	node script/utils/generateTsAbis.js

# Define a target to build the project
build:
	forge clean && forge build --build-info --build-info-path out/build-info/

# =============================================================
#         NEW UPGRADEABLE & ESPRESSO INTEGRATION TARGETS
# =============================================================

# Complete GTX Anvil setup (deploy both chains and configure) - LEGACY
setup-gtx-anvil-complete: check-env
	@echo "🚀 Setting up complete GTX Anvil system..."
	@$(MAKE) deploy-gtx-anvil-trading
	@echo ""
	@$(MAKE) deploy-gtx-anvil-2-chain-bm
	@echo ""
	@$(MAKE) configure-gtx-anvil-tokens
	@echo ""
	@echo "🎉 GTX Anvil complete setup finished!"

# Deploy core chain trading system (generalized)
deploy-core-chain-trading: check-env
	@echo "🚀 Deploying Core Chain Trading System..."
	forge script script/deployments/DeployCoreChainTrading.s.sol:DeployCoreChainTrading --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Deploy side chain tokens (step 1 of side chain setup)
# Usage: make deploy-side-chain-tokens network=gtx_anvil_2
deploy-side-chain-tokens: check-env
	@echo "🪙 Deploying Side Chain Tokens..."
	$(if $(SIDE_CHAIN),SIDE_CHAIN=$(SIDE_CHAIN),SIDE_CHAIN=$(call get_chain_name,$(network))) forge script script/deployments/DeploySideChainTokens.s.sol:DeploySideChainTokens --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Deploy side chain balance manager (step 2 of side chain setup, requires tokens)
# Usage: make deploy-side-chain-bm network=gtx_anvil_2 [core_chain=gtx-anvil]
deploy-side-chain-bm: check-env
	@echo "🚀 Deploying Side Chain Balance Manager..."
	$(if $(core_chain),@echo "📡 Using core chain: $(core_chain)",@echo "📡 Using default core chain: 31337")
	$(if $(core_chain),CORE_CHAIN=$(core_chain),CORE_CHAIN=31337) SIDE_CHAIN=$(call get_chain_name,$(network)) forge script script/deployments/DeploySideChainBalanceManager.s.sol:DeploySideChainBalanceManager --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# SPLIT SCRIPTS - Individual configuration steps (easier to debug)

# Step 1: Register side chain in ChainRegistry
register-side-chain: check-env
	@echo "📋 Registering Side Chain in ChainRegistry..."
	@echo "📡 Auto-detecting: CORE_CHAIN=$(call get_chain_name,$(network)), SIDE_DOMAIN=$(call get_paired_chain,$(network))"
	CORE_CHAIN=$(call get_chain_name,$(network)) SIDE_DOMAIN=$(call get_paired_chain,$(network)) forge script script/configuration/RegisterSideChain.s.sol:RegisterSideChain --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Step 2: Configure BalanceManager for cross-chain operations
configure-balance-manager: check-env
	@echo "⚙️ Configuring BalanceManager for Cross-Chain Operations..."
	@echo "📡 Auto-detecting: CORE_CHAIN=$(call get_chain_name,$(network)), SIDE_DOMAIN=$(call get_paired_chain,$(network))"
	CORE_CHAIN=$(call get_chain_name,$(network)) SIDE_DOMAIN=$(call get_paired_chain,$(network)) SIDE_CHAIN=$(call get_paired_chain,$(network)) forge script script/configuration/ConfigureBalanceManager.s.sol:ConfigureBalanceManager --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Step 3: Update core chain token mappings (cross-chain + local for depositLocal)
update-core-chain-mappings: check-env
	@echo "🪙 Updating Core Chain Token Mappings (Cross-chain + Local)..."
	@echo "⚠️  CRITICAL: This configures both cross-chain and local deposit functionality"
	@echo "📡 Auto-detecting: CORE_CHAIN=$(call get_chain_name,$(network)), SIDE_CHAIN=$(call get_paired_chain,$(network))"
	CORE_CHAIN=$(call get_chain_name,$(network)) SIDE_CHAIN=$(call get_paired_chain,$(network)) forge script script/configuration/UpdateCoreChainMappings.s.sol:UpdateCoreChainMappings --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)


# Update side chain token mappings (run after configure-cross-chain-tokens)
update-side-chain-mappings: check-env
	@echo "🔄 Updating Side Chain Token Mappings..."
	@echo "📡 Auto-detecting: SIDE_CHAIN=$(call get_chain_name,$(network)), CORE_CHAIN=$(call get_paired_chain,$(network))"
	SIDE_CHAIN=$(call get_chain_name,$(network)) CORE_CHAIN=$(call get_paired_chain,$(network)) forge script script/configuration/UpdateSideChainMappings.s.sol:UpdateSideChainMappings --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)


# Deploy native tokens and synthetic tokens on core chain
deploy-core-chain-tokens: check-env
	@echo "🪙 Deploying Core Chain Tokens..."
	@echo "📡 Auto-detecting: SIDE_CHAIN=$(call get_paired_chain,$(network))"
	SIDE_CHAIN=$(call get_paired_chain,$(network)) forge script script/deployments/DeployCoreChainTokens.s.sol:DeployCoreChainTokens --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Create trading pools on core chain  
# Usage: make create-trading-pools network=gtx_anvil
# Options: CREATE_NATIVE_POOLS=true CREATE_BRIDGE_POOLS=true
create-trading-pools: check-env
	@echo "🏊 Creating Trading Pools..."
	CORE_CHAIN=31337 $(if $(CREATE_NATIVE_POOLS),CREATE_NATIVE_POOLS=$(CREATE_NATIVE_POOLS),) $(if $(CREATE_BRIDGE_POOLS),CREATE_BRIDGE_POOLS=$(CREATE_BRIDGE_POOLS),) forge script script/deployments/CreateTradingPools.s.sol:CreateTradingPools --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Validate deployment before cross-chain testing
# Usage: make validate-deployment
validate-deployment:
	@echo "🔍 Running deployment validation script..."
	@echo "📝 Output will be logged to deployment.log"
	@./validate-deployment.sh

# Validate data population (trader balances, liquidity, trading events)
validate-data-population:
	@echo "🔍 Running data population validation script..."
	@echo "📝 Output will be logged to population.log"
	@./validate-data-population.sh

# Validate cross-chain deposit functionality
# Usage: make validate-cross-chain-deposit
validate-cross-chain-deposit:
	@echo "🔗 Running cross-chain deposit validation..."
	@echo "📝 Output will be logged to cross-chain-deposit.log"
	@./validate-cross-chain-deposit.sh

# Test cross-chain deposits (any chains, any token)
# Usage: make test-cross-chain-deposit network=gtx_anvil_2 side_chain=gtx-anvil-2 core_chain=gtx-anvil token=USDC amount=1000000000
test-cross-chain-deposit: check-env
	@echo "🔄 Testing cross-chain deposit..."
	$(if $(side_chain),@echo "📡 Side chain: $(side_chain)",@echo "📡 Side chain: auto-detect")
	$(if $(core_chain),@echo "📡 Core chain: $(core_chain)",@echo "📡 Core chain: gtx-anvil (default)")
	$(if $(token),@echo "🪙 Token: $(token)",@echo "🪙 Token: USDC (default)")
	$(if $(amount),@echo "💰 Amount: $(amount)",@echo "💰 Amount: auto (default)")
	$(if $(recipient),@echo "👤 Recipient: $(recipient)",)
	$(if $(side_chain),SIDE_CHAIN=$(side_chain),) $(if $(core_chain),CORE_CHAIN=$(core_chain),) $(if $(token),TOKEN_SYMBOL=$(token),) $(if $(amount),DEPOSIT_AMOUNT=$(amount),) $(if $(recipient),TEST_RECIPIENT=$(recipient),) forge script script/deposits/CrossChainDeposit.s.sol:TestCrossChainDeposit --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Test local deposits (same chain: regular token -> synthetic token)
# Usage: make test-local-deposit network=gtx_anvil token=USDC amount=1000000000
# Usage: make test-local-deposit network=gtx_anvil token=WETH amount=1000000000000000000 recipient=0x123...
test-local-deposit: check-env
	@echo "🏠 Testing local deposit..."
	@echo "📡 Network: $(network)"
	$(if $(token),@echo "🪙 Token: $(token)",@echo "🪙 Token: USDC (default)")
	$(if $(amount),@echo "💰 Amount: $(amount)",@echo "💰 Amount: auto (default)")
	$(if $(recipient),@echo "👤 Recipient: $(recipient)",@echo "👤 Recipient: deployer (default)")
	$(if $(token),TOKEN_SYMBOL=$(token),) $(if $(amount),DEPOSIT_AMOUNT=$(amount),) $(if $(recipient),TEST_RECIPIENT=$(recipient),) forge script script/deposits/LocalDeposit.s.sol:LocalDeposit --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Fill orderbook with limit orders (default ETH/USDC pairs)
# Usage: make fill-orderbook network=gtx_anvil
fill-orderbook: check-env
	@echo "📈 Filling orderbook with limit orders..."
	@echo "📡 Network: $(network)"
	@echo "🪙 Trading pair: gsWETH/gsUSDC (default)"
	forge script script/trading/FillOrderBook.s.sol:FillMockOrderBook --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Fill orderbook with custom parameters
# Usage: make fill-orderbook-custom network=gtx_anvil buy_start=1900000000 buy_end=1980000000 sell_start=2000000000 sell_end=2100000000 price_step=10000000 num_orders=10 buy_qty=10000000000000000 sell_qty=10000000000000000 eth_amount=200000000000000000000 usdc_amount=400000000000
fill-orderbook-custom: check-env
	@echo "📈 Filling orderbook with custom parameters..."
	@echo "📡 Network: $(network)"
	$(if $(buy_start),@echo "📊 Buy start price: $(buy_start)",@echo "📊 Buy start price: 1900000000 (default)")
	$(if $(buy_end),@echo "📊 Buy end price: $(buy_end)",@echo "📊 Buy end price: 1980000000 (default)")
	$(if $(sell_start),@echo "📊 Sell start price: $(sell_start)",@echo "📊 Sell start price: 2000000000 (default)")
	$(if $(sell_end),@echo "📊 Sell end price: $(sell_end)",@echo "📊 Sell end price: 2100000000 (default)")
	BUY_START_PRICE=$(or $(buy_start),1900000000) BUY_END_PRICE=$(or $(buy_end),1980000000) SELL_START_PRICE=$(or $(sell_start),2000000000) SELL_END_PRICE=$(or $(sell_end),2100000000) PRICE_STEP=$(or $(price_step),10000000) NUM_ORDERS=$(or $(num_orders),10) BUY_QUANTITY=$(or $(buy_qty),10000000000000000) SELL_QUANTITY=$(or $(sell_qty),10000000000000000) ETH_AMOUNT=$(or $(eth_amount),200000000000000000000) USDC_AMOUNT=$(or $(usdc_amount),400000000000) forge script script/trading/FillOrderBook.s.sol:FillMockOrderBook --sig "runConfigurable(uint128,uint128,uint128,uint128,uint128,uint8,uint128,uint128,uint256,uint256)" $(or $(buy_start),1900000000) $(or $(buy_end),1980000000) $(or $(sell_start),2000000000) $(or $(sell_end),2100000000) $(or $(price_step),10000000) $(or $(num_orders),10) $(or $(buy_qty),10000000000000000) $(or $(sell_qty),10000000000000000) $(or $(eth_amount),200000000000000000000) $(or $(usdc_amount),400000000000) --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Execute market orders (buy and sell)
# Usage: make market-order network=gtx_anvil
market-order: check-env
	@echo "🔄 Executing market orders..."
	@echo "📡 Network: $(network)"
	@echo "🪙 Trading pair: WETH/USDC"
	@echo "⚡ Executing both market buy and sell orders"
	forge script script/trading/MarketOrderBook.sol:MarketOrderBook --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Usage: make transfer-tokens network=gtx_anvil recipient=0x123... token=USDC amount=1000000000
transfer-tokens: check-env
	@echo "💸 Transferring tokens..."
	@echo "📡 Network: $(network)"
	$(if $(recipient),@echo "👤 Recipient: $(recipient)",$(error "recipient parameter is required"))
	$(if $(token),@echo "🪙 Token: $(token)",$(error "token parameter is required"))
	$(if $(amount),@echo "💰 Amount: $(amount)",$(error "amount parameter is required"))
	RECIPIENT=$(recipient) TOKEN_SYMBOL=$(token) AMOUNT=$(amount) forge script script/utils/TransferTokens.s.sol:TransferTokens --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)


# Diagnose market order issues 
# Usage: make diagnose-market-order network=gtx_anvil
diagnose-market-order: check-env
	@echo "🔍 Diagnosing market order issues..."
	@echo "📡 Network: $(network)"
	forge script script/trading/DiagnoseMarketOrder.s.sol:DiagnoseMarketOrder --rpc-url $(call get_rpc_url,$(network)) --broadcast $(flag)

# Complete two-chain setup (requires setting network for each step)
setup-two-chain-complete: check-env
	@echo "🚀 Setting up complete two-chain system..."
	@echo "Note: This requires manually setting network for each step"
	@echo "1. Run: make deploy-core-chain-trading network=<core_network>"
	@echo "2. Run: make deploy-side-chain-bm network=<side_network>  # Automatically loads core chain BalanceManager"  
	@echo "3. Run: make configure-chain-tokens network=<core_network>"

# Deploy upgradeable GTX to all chains
deploy-upgradeable-all: check-env
	@echo "🚀 Deploying to all chains with upgradeability..."
	@$(MAKE) deploy-upgradeable-rari
	@echo ""
	@$(MAKE) deploy-upgradeable-appchain
	@echo ""
	@$(MAKE) deploy-upgradeable-arbitrum
	@echo ""
	@$(MAKE) deploy-upgradeable-gtx-anvil
	@echo ""
	@$(MAKE) deploy-upgradeable-gtx-anvil-2
	@echo ""
	@echo "🎉 All upgradeable contracts deployed!"
	@echo "📋 Update proxy addresses in .env for instant upgrades"
	
# Define a target to display help information
help:
	@echo "=== GTX CLOB DEX - Upgradeable Contracts with Espresso Hyperlane ==="
	@echo ""
	@echo "🚀 Quick Start Commands:"
	@echo ""
	@echo "🔥 Two-Chain Deployment (Generalized):"
	@echo "  deploy-core-chain-trading       - Deploy core chain trading system"
	@echo "  deploy-side-chain-bm            - Deploy side chain balance manager"
	@echo "  configure-cross-chain-tokens    - Configure cross-chain token mappings"
	@echo "    register-side-chain           - Step 1: Register side chain in ChainRegistry"
	@echo "    configure-balance-manager     - Step 2: Configure BalanceManager for cross-chain"
	@echo "    update-core-chain-mappings    - Step 3: Update core chain token mappings"
	@echo "  deploy-core-chain-tokens        - Deploy tokens (no pools)"
	@echo "  create-trading-pools            - Create all required trading pools"
	@echo "  validate-deployment             - Validate deployment (including pools)"
	@echo "  validate-data-population        - Validate data population (balances, liquidity, events)"
	@echo "  test-cross-chain-deposit        - Test cross-chain deposits (any chains)"
	@echo "  test-local-deposit              - Test local deposits (same chain)"
	@echo "  transfer-tokens                 - Transfer tokens to another address"
	@echo "  fill-orderbook                  - Fill orderbook with default limit orders"
	@echo "  fill-orderbook-custom           - Fill orderbook with custom parameters"
	@echo "  market-order                    - Execute market orders (buy and sell)"
	@echo "  diagnose-market-order          - Debug market order issues"
	@echo "  setup-two-chain-complete        - Instructions for complete setup"
	@echo ""
	@echo "🏗️  GTX Anvil Deployment (Legacy):"
	@echo "  deploy-gtx-anvil-trading        - Deploy GTX Anvil core trading system"
	@echo "  deploy-gtx-anvil-2-chain-bm     - Deploy GTX Anvil 2 chain balance manager"
	@echo "  configure-gtx-anvil-tokens      - Configure token registry and mappings"
	@echo "  setup-gtx-anvil-complete        - Complete GTX Anvil setup (all steps)"
	@echo ""
	@echo "📋 Legacy CLOB Commands:"
	@echo "  deploy                          - Deploy contracts using the specified network"
	@echo "  deploy-verify                   - Deploy and verify contracts"
	@echo "  deploy-mocks                    - Deploy mock contracts"
	@echo "  swap                            - Execute token swaps"
	@echo "  simple-integration              - Run simple integration sequence"
	@echo "  full-integration                - Run full deployment and testing"
	@echo ""
	@echo "🔧 Development Commands:"
	@echo "  compile                         - Compile the contracts"
	@echo "  test                            - Run tests"
	@echo "  lint                            - Lint the code"
	@echo "  generate-abi                    - Generate ABI files"
	@echo "  build                           - Build project with build info"
	@echo ""
	@echo "📋 Required Environment Variables (.env):"
	@echo "  PRIVATE_KEY=0x123..."
	@echo ""
