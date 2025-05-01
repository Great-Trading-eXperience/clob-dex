-include .env

# Default values
# DEFAULT_NETWORK := arbitrumSepolia
DEFAULT_NETWORK := default_network
FORK_NETWORK := mainnet

# Custom network can be set via make network=<network_name>
network ?= $(DEFAULT_NETWORK)

.PHONY: account chain compile deploy deploy-verify flatten fork format generate lint test verify upgrade upgrade-verify

# Helper function to run forge script
define forge_script
	forge script script/Deploy.s.sol:Deploy --rpc-url $(network) -vvvv --broadcast --via-ir --force
endef

# Helper function to run upgrade script
define forge_upgrade_script
 forge script script/UpgradeBeaconProxies.s.sol:UpgradeBeaconProxies --rpc-url $(network) -vvvv --broadcast --via-ir --force
endef

# Helper function to run mock deployment script
define forge_deploy_mocks
	forge script script/DeployMocks.s.sol:DeployMocks --rpc-url $(network) -vvvv --broadcast --via-ir --force
endef

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


# Define a target to verify contracts using the specified network
verify:
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
	node script/generateTsAbis.js

# Define a target to build the project
build:
	forge build --build-info --build-info-path out/build-info/

# Define a target to display help information
help:
	@echo "Makefile targets:"
	@echo "  deploy          - Deploy contracts using the specified network"
	@echo "  deploy-verify   - Deploy and verify contracts using the specified network"
	@echo "  upgrade         - Upgrade contracts using the specified network"
	@echo "  upgrade-verify  - Upgrade and verify contracts using the specified network"
	@echo "  verify          - Verify contracts using the specified network"
	@echo "  compile         - Compile the contracts"
	@echo "  test            - Run tests"
	@echo "  lint            - Lint the code"
	@echo "  generate-abi    - Generate ABI files"
	@echo "  help            - Display this help information"