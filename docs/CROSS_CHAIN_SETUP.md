# Cross-Chain Infrastructure Setup

This document outlines the cross-chain infrastructure components and setup procedures for the GTX CLOB DEX on Espresso testnet.

## Overview

The cross-chain infrastructure consists of three main components:

1. **ChainRegistry** - Manages chain configurations and Hyperlane mailbox addresses
2. **TokenRegistry** - Maps source tokens to synthetic tokens across chains  
3. **SyntheticTokenFactory** - Creates and manages synthetic tokens for cross-chain assets

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   ChainRegistry │    │  TokenRegistry  │    │SyntheticTokenFactory│
│                 │    │                 │    │                 │
│ • Chain configs │    │ • Token mappings│    │ • Creates tokens│
│ • Mailbox addrs │    │ • Decimal conv. │    │ • Manages supply│
│ • Domain IDs    │    │ • Active status │    │ • Integrates    │
│                 │    │                 │    │   with registry │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │  Hyperlane      │
                    │  Cross-chain    │
                    │  Messaging      │
                    └─────────────────┘
```

## Espresso Testnet Configuration

### Supported Chains

| Chain | Chain ID | Domain ID | Mailbox Address |
|-------|----------|-----------|-----------------|
| Rari Testnet | 1918988905 | 1918988905 | 0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358 |
| Appchain Testnet | 4661 | 4661 | 0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1 |
| Arbitrum Sepolia | 421614 | 421614 | 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766 |
| Ethereum Sepolia | 11155111 | 11155111 | 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766 |

### Default Token Mappings

| Source Token | Source Chain | Target Chain | Synthetic Token | Symbol |
|--------------|--------------|--------------|-----------------|--------|
| 0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516 | Appchain (4661) | Rari (1918988905) | 0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68 | gsUSDT |
| 0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F | Appchain (4661) | Rari (1918988905) | 0xC7A1777e80982E01e07406e6C6E8B30F5968F836 | gsWETH |
| 0xb2e9Eabb827b78e2aC66bE17327603778D117d18 | Appchain (4661) | Rari (1918988905) | 0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF | gsWBTC |

## Deployment Guide

### Step 1: Deploy Individual Components

#### Deploy ChainRegistry
```bash
forge script script/DeployChainRegistry.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

#### Deploy TokenRegistry  
```bash
forge script script/DeployTokenRegistry.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

#### Deploy SyntheticTokenFactory
```bash
# Set environment variables
export TOKEN_REGISTRY_ADDRESS=0x...  # From previous step
export BRIDGE_RECEIVER_ADDRESS=0x... # Your bridge contract

forge script script/DeploySyntheticTokenFactory.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### Step 2: Complete Infrastructure Setup

```bash
# Deploy all components and configure Espresso testnet
forge script script/CrossChainSetup.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### Step 3: Verify Deployment

```bash
# Set environment variables for deployed contracts
export CHAIN_REGISTRY_ADDRESS=0x...
export TOKEN_REGISTRY_ADDRESS=0x...
export SYNTHETIC_TOKEN_FACTORY_ADDRESS=0x...

# Run verification
forge script script/VerifyCrossChainSetup.s.sol --rpc-url $RPC_URL
```

## Usage Examples

### Creating Synthetic Tokens

```solidity
// Create synthetic USDC for Polygon -> Arbitrum
address syntheticUSDC = factory.createSyntheticToken(
    137,                    // Polygon chain ID
    0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC on Polygon
    42161,                  // Arbitrum chain ID
    "Synthetic USDC",       // Name
    "sUSDC",               // Symbol
    6,                     // Source decimals
    6                      // Synthetic decimals
);
```

### Batch Token Creation

```solidity
SyntheticTokenFactoryStorage.TokenCreationParams[] memory params = 
    new SyntheticTokenFactoryStorage.TokenCreationParams[](2);

params[0] = SyntheticTokenFactoryStorage.TokenCreationParams({
    sourceChainId: 137,
    sourceToken: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174,
    name: "Synthetic USDC",
    symbol: "sUSDC",
    sourceDecimals: 6,
    syntheticDecimals: 6
});

params[1] = SyntheticTokenFactoryStorage.TokenCreationParams({
    sourceChainId: 137,
    sourceToken: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,
    name: "Synthetic WETH",
    symbol: "sWETH",
    sourceDecimals: 18,
    syntheticDecimals: 18
});

address[] memory syntheticTokens = factory.batchCreateSyntheticTokens(params, 42161);
```

### Querying Token Information

```solidity
// Get synthetic token address
address synthetic = tokenRegistry.getSyntheticToken(sourceChainId, sourceToken, targetChainId);

// Get source token from synthetic (reverse lookup)
(uint32 sourceChain, address sourceToken) = tokenRegistry.getSourceToken(targetChainId, syntheticToken);

// Check if mapping is active
bool isActive = tokenRegistry.isTokenMappingActive(sourceChainId, sourceToken, targetChainId);

// Convert amounts between decimals
uint256 syntheticAmount = tokenRegistry.convertAmount(1000000, 6, 18); // 1 USDC -> 18 decimals
```

## Integration with CLOB DEX

### Cross-Chain Order Flow

1. **User deposits tokens on source chain** (e.g., Appchain)
2. **Bridge locks tokens and mints synthetics** on target chain (e.g., Rari)
3. **User trades synthetic tokens** on Rari CLOB
4. **User withdraws** - synthetics burned, original tokens unlocked

### Balance Manager Integration

```solidity
// In ChainBalanceManager.sol
function processCrossChainDeposit(
    uint32 sourceChainId,
    address sourceToken,
    address user,
    uint256 amount
) external {
    // Get synthetic token address
    address syntheticToken = tokenRegistry.getSyntheticToken(
        sourceChainId, 
        sourceToken, 
        block.chainid
    );
    
    // Convert amount to local decimals
    uint256 localAmount = tokenRegistry.convertAmountForMapping(
        sourceChainId,
        sourceToken,
        block.chainid,
        amount,
        true // source to synthetic
    );
    
    // Credit user's balance
    _increaseBalance(user, Currency.wrap(syntheticToken), localAmount);
}
```

## Security Considerations

1. **Ownership Management**
   - ChainRegistry: Keep owner as deployer for chain management
   - TokenRegistry: Transfer to SyntheticTokenFactory for automated registration
   - SyntheticTokenFactory: Keep owner as deployer for token creation

2. **Bridge Receiver**
   - Set to actual bridge contract address (not deployer)
   - Only bridge receiver can mint/burn synthetic tokens
   - Implement proper access controls

3. **Token Mappings**
   - Verify token addresses before creating mappings
   - Use consistent decimal handling
   - Monitor active/inactive status

## Monitoring and Maintenance

### Key Metrics to Monitor

- Total synthetic tokens created
- Active vs inactive token mappings
- Cross-chain transfer volumes
- Failed bridge transactions

### Maintenance Tasks

- Update chain configurations as needed
- Add new token mappings for supported assets
- Deactivate compromised or deprecated tokens
- Upgrade contracts using beacon proxy pattern

## Troubleshooting

### Common Issues

1. **Token mapping already exists**
   - Check existing mappings before creating new ones
   - Use update functions for modifications

2. **Unauthorized access errors**
   - Verify contract ownership
   - Ensure proper role assignments

3. **Decimal conversion errors**
   - Verify source and target token decimals
   - Test conversions with small amounts first

### Recovery Procedures

1. **Contract upgrades**: Use beacon proxy upgrade mechanism
2. **Emergency pause**: Implement pause functionality in bridge receiver
3. **Token recovery**: Admin functions for stuck tokens (if implemented)

## Testing

Run the test suite to verify functionality:

```bash
# Test individual components
forge test --match-contract ChainRegistryTest
forge test --match-contract TokenRegistryTest  
forge test --match-contract SyntheticTokenFactoryTest

# Test integration
forge test --match-contract CrossChainIntegrationTest
```

## Support

For technical support or questions:
- Review test files for usage examples
- Check contract events for debugging
- Use verification script to diagnose issues