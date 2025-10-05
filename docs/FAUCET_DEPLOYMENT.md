# Faucet Deployment Guide

This guide covers the deployment and setup of the faucet system using the scripts in `/script/faucet/` and the provided Makefile commands.

## Overview

The faucet system consists of:
- **Beacon**: An upgradeable proxy beacon for the Faucet contract
- **Proxy**: A beacon proxy instance of the Faucet contract
- **Mock Tokens**: WETH and USDC test tokens for the faucet to distribute
- **Configuration**: Faucet amount and cooldown settings

## Prerequisites

1. Set up environment variables in `.env`:
   ```bash
   PRIVATE_KEY=<your_deployer_private_key>
   OWNER_ADDRESS=<beacon_owner_address>  # Optional, defaults to deployer
   ```

2. Ensure you have sufficient funds on the target network for deployment and gas fees.

3. Install dependencies:
   ```bash
   forge install
   ```

## Quick Deployment

Deploy the complete faucet system with a single command:

```bash
make deploy-faucet network=<network_name>
```

This command will automatically:
1. Deploy the faucet beacon and proxy
2. Configure faucet settings (amount and cooldown)
3. Add mock tokens (WETH and USDC)
4. Deposit initial token supplies to the faucet

### Supported Networks

Use any of the configured networks:
- `gtx_core_devnet` - Local Anvil instance (https://core-devnet.gtxdex.xyz)
- `gtx_side_devnet` - Side chain Anvil (https://side-devnet.gtxdex.xyz)
- `rari_testnet` - Rari testnet
- `appchain_testnet` - Appchain testnet
- `arbitrum_sepolia` - Arbitrum Sepolia

## Step-by-Step Deployment

### 1. Deploy Faucet Contract

Deploy the beacon and proxy contracts:

```bash
make deploy-faucet network=<network_name>
```

**Script**: `script/faucet/DeployFaucet.s.sol:DeployFaucet`

This step:
- Deploys an upgradeable beacon for the Faucet contract
- Deploys a beacon proxy instance
- Initializes the proxy with the owner address
- Saves deployment addresses to `deployments/<chain_id>.json`

### 2. Configure Faucet Settings

Set up the faucet amount and cooldown:

```bash
make setup-faucet network=<network_name>
```

**Script**: `script/faucet/SetupFaucet.s.sol:SetupFaucet`

This step:
- Sets the faucet amount to `1e12` (1,000,000 tokens with 6 decimals)
- Sets the cooldown period to `1` second
- Can be customized by modifying the script

### 3. Add Tokens to Faucet

Add mock tokens that the faucet can distribute:

```bash
make add-faucet-tokens network=<network_name>
```

**Script**: `script/faucet/AddToken.s.sol:AddToken`

This step:
- Adds WETH and USDC mock tokens to the faucet's available tokens list
- Mints initial supplies:
  - 1,000 WETH (1000e18)
  - 2,000,000 USDC (2_000_000e6)

### 4. Deposit Additional Tokens (Optional)

Deposit more tokens to the faucet:

```bash
make deposit-faucet-tokens network=<network_name>
```

**Script**: `script/faucet/DepositToken.s.sol:DepositToken`

This step:
- Mints additional tokens to the deployer
- Approves and deposits tokens to the faucet
- Default deposit amount: `1e24` tokens

## Verification

To deploy with contract verification:

```bash
make deploy-faucet-verify network=<network_name>
```

## Configuration Details

### Faucet Settings

- **Faucet Amount**: `1e12` (1,000,000 tokens with 6 decimals)
- **Cooldown**: `1` second between requests
- **Owner**: Specified in `OWNER_ADDRESS` env var or defaults to deployer

### Token Supplies

- **WETH**: 1,000 tokens (18 decimals)
- **USDC**: 2,000,000 tokens (6 decimals)

### Deployment Files

Deployment addresses are saved to:
```
deployments/<chain_id>.json
```

Key addresses:
- `BEACON_FAUCET`: The upgradeable beacon contract
- `PROXY_FAUCET`: The faucet proxy contract (main interface)
- `MOCK_TOKEN_WETH`: WETH mock token contract
- `MOCK_TOKEN_USDC`: USDC mock token contract

## Usage After Deployment

Once deployed, users can request tokens from the faucet by calling:

```solidity
faucet.requestTokens(tokenAddress)
```

The faucet will distribute the configured amount of the requested token, subject to the cooldown period.

## Available Makefile Commands

The following Makefile targets are available for faucet deployment:

```bash
# Deploy faucet beacon and proxy
make deploy-faucet network=<network_name>

# Deploy with contract verification
make deploy-faucet-verify network=<network_name>

# Configure faucet settings (amount and cooldown)
make setup-faucet network=<network_name>

# Add mock tokens to faucet
make add-faucet-tokens network=<network_name>

# Deposit additional tokens to faucet
make deposit-faucet-tokens network=<network_name>
```

## Troubleshooting

### Common Issues

1. **Insufficient Funds**: Ensure the deployer account has enough native tokens for gas fees.

2. **Missing Environment Variables**: Verify `.env` file contains `PRIVATE_KEY`.

3. **Network Configuration**: Check that the network name matches the configured networks in the Makefile.

4. **Token Deployment**: If mock tokens aren't deployed, they need to be deployed separately before running faucet scripts.

### Checking Deployment Status

Verify the faucet is properly deployed and configured:

```bash
# Check if beacon and proxy are deployed
forge script script/faucet/DeployFaucet.s.sol:DeployFaucet --rpc-url <network> --dry-run

# Verify faucet configuration
cast call <PROXY_FAUCET_ADDRESS> "getFaucetAmount()" --rpc-url <network>
cast call <PROXY_FAUCET_ADDRESS> "getCooldown()" --rpc-url <network>
cast call <PROXY_FAUCET_ADDRESS> "getAvailableTokensLength()" --rpc-url <network>
```

### Debug Output

For verbose debugging output, add the `-vvv` flag:

```bash
make deploy-faucet network=<network_name> flag="-vvv"
```

## Custom Deployment Flags

Add custom flags for debugging or specific requirements:

```bash
make deploy-faucet network=<network_name> flag="--gas-limit 3000000 -vvv"
```

Common flags:
- `--gas-limit <amount>`: Set custom gas limit
- `-vvv`: Verbose output for debugging
- `--verify`: Verify contracts on block explorer
- `--dry-run`: Simulate without broadcasting
- `--skip-simulation`: Skip simulation step

## Example Deployment Flow

Here's a complete example of deploying the faucet on the local anvil network:

```bash
# 1. Set environment variables
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# 2. Deploy the complete faucet system
make deploy-faucet network=gtx_core_devnet

# 3. Verify deployment
cast call <PROXY_FAUCET_ADDRESS> "getFaucetAmount()" --rpc-url https://core-devnet.gtxdex.xyz
cast call <PROXY_FAUCET_ADDRESS> "getCooldown()" --rpc-url https://core-devnet.gtxdex.xyz

# 4. Test faucet functionality
cast send <PROXY_FAUCET_ADDRESS> "requestTokens(address)" <WETH_TOKEN_ADDRESS> \
  --private-key $PRIVATE_KEY --rpc-url https://core-devnet.gtxdex.xyz
```

## Script Details

### DeployFaucet.s.sol

**Location**: `script/faucet/DeployFaucet.s.sol:18`

- Deploys upgradeable beacon using OpenZeppelin's Upgrades library
- Creates beacon proxy instance
- Initializes proxy with owner address
- Exports deployment addresses to JSON

### SetupFaucet.s.sol

**Location**: `script/faucet/SetupFaucet.s.sol:35`

- Updates faucet amount to `1e12` (1M tokens with 6 decimals)
- Sets cooldown period to `1` second
- Logs configuration changes

### AddToken.s.sol

**Location**: `script/faucet/AddToken.s.sol:52`

- Adds WETH and USDC tokens to faucet's available tokens
- Mints initial token supplies to the faucet
- Logs token addition and minting operations

### DepositToken.s.sol

**Location**: `script/faucet/DepositToken.s.sol:48`

- Mints additional tokens to deployer
- Approves faucet contract for token spending
- Deposits tokens to faucet contract

## Security Considerations

1. **Owner Address**: The beacon owner has upgrade rights. Use a secure address for production deployments.

2. **Private Key**: Never commit private keys to version control. Use environment variables.

3. **Faucet Amount**: Configure appropriate amounts to prevent abuse while ensuring usability.

4. **Cooldown Period**: Set reasonable cooldown periods to prevent spam requests.

## Integration with Main System

The faucet system integrates with the main GTX trading system by providing test tokens that can be used for:

1. **Cross-chain deposits**: Tokens from faucet can be deposited via side chain
2. **Local deposits**: Tokens can be deposited directly on core chain
3. **Trading**: Users can trade with faucet-distributed tokens after depositing

For complete system deployment, deploy the faucet first, then proceed with the main GTX system deployment as documented in `DEPLOYMENT.md`.