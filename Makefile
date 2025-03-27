-include .env

# Default values
DEFAULT_NETWORK := default_network
FORK_NETWORK := mainnet

# Custom network can be set via make network=<network_name>
network ?= $(DEFAULT_NETWORK)

.PHONY: account chain compile deploy deploy-verify flatten fork format generate lint test verify

# Helper function to run forge script
define forge_script
	forge script script/Deploy.s.sol --rpc-url $(network) --broadcast --legacy $(1)
endef

# Helper function to run forge script
define deploy_tokens
	forge script script/DeployTokens.s.sol --rpc-url $(network) --broadcast --legacy $(1)
endef

# Helper function to run forge script
define deploy_vaults
	forge script script/DeployVaults.s.sol --rpc-url $(network) --broadcast --legacy $(1)
endef

# Helper function to run forge script
define deploy_managers
	forge script script/DeployManagers.s.sol --rpc-url $(network) --broadcast --legacy $(1)
endef

# Helper function to run forge script
define deploy_orderbooks
	forge script script/DeployOrderBooks.s.sol --rpc-url $(network) --broadcast --legacy $(1)
endef

# Helper function to run forge script
define place_orders
	forge script script/PlaceOrders.s.sol --rpc-url $(network) --broadcast -vvv --legacy
endef

# Helper function to run forge script
define place_orders_full
	forge script script/PlaceOrdersFull.s.sol --rpc-url $(network) --broadcast -vvv --legacy
endef

# Define a target to deploy using the specified network
deploy: build
	$(call forge_script,)
	$(MAKE) generate-abi

# Define a target to deploy using the specified network
deploy-tokens: build
	$(call deploy_tokens,)
	$(MAKE) generate-abi

# Define a target to deploy using the specified network
deploy-vaults: build
	$(call deploy_vaults,)
	$(MAKE) generate-abi

# Define a target to deploy using the specified network
deploy-managers: build
	$(call deploy_managers,)
	$(MAKE) generate-abi

# Define a target to deploy using the specified network
deploy-orderbooks: build
	$(call deploy_orderbooks,)
	$(MAKE) generate-abi

# Define a target to deploy using the specified network
place-orders: build
	$(call place_orders,)
	$(MAKE) generate-abi

# Define a target to deploy using the specified network
place-orders-full: build
	$(call place_orders_full,)
	$(MAKE) generate-abi

# Define a target to verify contracts using the specified network
verify: build
	forge script script/VerifyAll.s.sol --ffi --rpc-url $(network)

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

# Define a target to build the project
build:
	forge build --build-info --build-info-path out/build-info/

# Define a target to display help information
help:
	@echo "Makefile targets:"
	@echo "  deploy          - Deploy contracts using the specified network"
	@echo "  deploy-verify   - Deploy and verify contracts using the specified network"
	@echo "  verify          - Verify contracts using the specified network"
	@echo "  compile         - Compile the contracts"
	@echo "  test            - Run tests"
	@echo "  lint            - Lint the code"
	@echo "  generate-abi    - Generate ABI files"
	@echo "  help            - Display this help information"