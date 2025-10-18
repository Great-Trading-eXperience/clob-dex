# Cross-Chain Token Mappings Documentation

## Overview

This document describes the token mapping configuration for the CLOB DEX cross-chain infrastructure. The system enables users to deposit tokens on source chains (Appchain, Rise Sepolia, Arbitrum Sepolia) and automatically mint corresponding synthetic tokens on the host chain (Rari Testnet).

## Architecture

### Components

1. **ChainBalanceManager** - Deployed on source chains, handles deposits and cross-chain messaging
2. **BalanceManager** - Deployed on Rari (host chain), handles synthetic token minting/burning
3. **Synthetic Tokens** - ERC20 tokens on Rari representing deposited assets (gsUSDT, gsWETH, gsWBTC)
4. **Hyperlane** - Cross-chain messaging protocol enabling communication between chains

### Flow

```
Source Chain (Appchain/Rise/Arbitrum)     →     Host Chain (Rari)
┌─────────────────────────────────┐              ┌──────────────────────────┐
│  User deposits USDT             │              │                          │
│  ↓                              │              │                          │
│  ChainBalanceManager            │   Hyperlane  │  BalanceManager          │
│  - Validates token              │   Message    │  - Receives message      │
│  - Takes custody                │   -------→   │  - Mints gsUSDT          │
│  - Sends cross-chain message    │              │  - Credits user balance  │
└─────────────────────────────────┘              └──────────────────────────┘
```

## Deployed Contracts

### Rari Testnet (Host Chain)
- **Chain ID**: 1918988905
- **Domain ID**: 1918988905
- **RPC**: https://rari.caff.testnet.espresso.network
- **Mailbox**: `0x393EE49dA6e6fB9Ab32dd21D05096071cc7d9358`

**Contracts:**
- **BalanceManager**: `0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5`
- **ChainRegistry**: `0x0a1Ced1539C9FB81aBdDF870588A4fEfBf461bBB`
- **TokenRegistry**: `0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E`
- **SyntheticTokenFactory**: `0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC`

**Synthetic Tokens:**
- **gsUSDT**: `0x8bA339dDCC0c7140dC6C2E268ee37bB308cd4C68`
- **gsWETH**: `0xC7A1777e80982E01e07406e6C6E8B30F5968F836`
- **gsWBTC**: `0x996BB75Aa83EAF0Ee2916F3fb372D16520A99eEF`

### Appchain Testnet (Source Chain)
- **Chain ID**: 4661
- **Domain ID**: 4661
- **RPC**: https://appchain.caff.testnet.espresso.network
- **Mailbox**: `0xc8d6B960CFe734452f2468A2E0a654C5C25Bb6b1`

**Contracts:**
- **ChainBalanceManager**: `0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7`

**Source Tokens:**
- **USDT**: `0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516`
- **WETH**: `0x4200000000000000000000000000000000000006`
- **WBTC**: `0x68194a729C2450ad26072b3D33ADaCbcef39D574`

### Rise Sepolia (Source Chain)
- **Chain ID**: 11155931
- **Domain ID**: 11155931
- **RPC**: https://indexing.testnet.riselabs.xyz/
- **Mailbox**: `0xD377bFbea110cDbc3D31EaFB146AE6fA5b3190E3`

**Contracts:**
- **ChainBalanceManager**: `0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745`

**Source Tokens:**
- **USDT**: `0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6`
- **WETH**: `0x567a076BEEF17758952B05B1BC639E6cDd1A31EC`
- **WBTC**: `0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E`

### Arbitrum Sepolia (Source Chain)
- **Chain ID**: 421614
- **Domain ID**: 421614
- **RPC**: https://sepolia-rollup.arbitrum.io/rpc
- **Mailbox**: `0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766`

**Contracts:**
- **ChainBalanceManager**: `0xb37C1B87648B93Ab8A0d32cA7d22e25e78B0e67f`

**Source Tokens:**
- **USDT**: `0xA0b86a33E6373C0e2E33Df4B43A8F6f98cb58e38`
- **WETH**: `0x980B62Da83eFf3D4576C647993b0c1D7faf17c73`
- **WBTC**: `0x5ea8d4871dc1c2f8df8b6c1b6e94e4c4b943dd09`

## Token Mappings

### Cross-Chain Token Mapping Table

| Source Chain | Source Token | Token Address | → | Synthetic Token | Rari Address |
|--------------|--------------|---------------|---|-----------------|--------------|
| **Appchain** | USDT | `0x1362...3a7516` | → | gsUSDT | `0x8bA3...cd4C68` |
| **Appchain** | WETH | `0x4200...000006` | → | gsWETH | `0xC7A1...68F836` |
| **Appchain** | WBTC | `0x6819...39D574` | → | gsWBTC | `0x996B...A99eEF` |
| **Rise Sepolia** | USDT | `0x9766...77485f6` | → | gsUSDT | `0x8bA3...cd4C68` |
| **Rise Sepolia** | WETH | `0x567a...C639E6cDd1A31EC` | → | gsWETH | `0xC7A1...68F836` |
| **Rise Sepolia** | WBTC | `0xc6b3...a25bF0E` | → | gsWBTC | `0x996B...A99eEF` |
| **Arbitrum Sepolia** | USDT | `0xa0B8...cb58e38` | → | gsUSDT | `0x8bA3...cd4C68` |
| **Arbitrum Sepolia** | WETH | `0x980B...af17c73` | → | gsWETH | `0xC7A1...68F836` |
| **Arbitrum Sepolia** | WBTC | `0x5ea8...943dd09` | → | gsWBTC | `0x996B...A99eEF` |

## Configuration Process

### 1. Deployment

The system was deployed using the `DeployEspressoTestnet.s.sol` script:

```bash
# Deploy complete system on Rari
NETWORK=rari forge script script/DeployEspressoTestnet.s.sol --rpc-url https://rari.caff.testnet.espresso.network --broadcast --private-key $PRIVATE_KEY

# Deploy ChainBalanceManager on source chains
NETWORK=appchain forge script script/DeployEspressoTestnet.s.sol --rpc-url https://appchain.caff.testnet.espresso.network --broadcast --private-key $PRIVATE_KEY
```

### 2. Token Mapping Setup

Token mappings were configured using the `SetupTokenMappings.s.sol` script:

```bash
# Setup mappings on each source chain
NETWORK=appchain forge script script/SetupTokenMappings.s.sol --rpc-url https://appchain.caff.testnet.espresso.network --broadcast --private-key $PRIVATE_KEY

NETWORK=rise-sepolia forge script script/SetupTokenMappings.s.sol --rpc-url https://indexing.testnet.riselabs.xyz/ --broadcast --private-key $PRIVATE_KEY

NETWORK=arbitrum-sepolia forge script script/SetupTokenMappings.s.sol --rpc-url https://sepolia-rollup.arbitrum.io/rpc --broadcast --private-key $PRIVATE_KEY
```

### 3. Configuration Verification

The setup script performs the following actions:
1. **Whitelist tokens** on ChainBalanceManager
2. **Set token mappings** (source token → synthetic token)
3. **Verify mappings** are correctly stored
4. **Confirm whitelist status** of all tokens

## Usage

### Depositing Tokens (Cross-Chain Bridge)

To deposit tokens and mint synthetic tokens on Rari:

```solidity
// On any source chain (Appchain, Rise, Arbitrum)
ChainBalanceManager chainBalanceManager = ChainBalanceManager(CBM_ADDRESS);

// Approve tokens first
IERC20(USDT_ADDRESS).approve(CBM_ADDRESS, amount);

// Deposit tokens - automatically bridges to Rari and mints gsUSDT for recipient
chainBalanceManager.deposit(
    USDT_ADDRESS,     // Source token
    amount,           // Amount to deposit
    recipient         // Address to receive gsUSDT on Rari
);
```

### Key Functions

#### ChainBalanceManager (Source Chains)

```solidity
// Main deposit function - automatically bridges to synthetic tokens
function deposit(address token, uint256 amount, address recipient) external payable;

// Check if token is whitelisted
function isTokenWhitelisted(address token) external view returns (bool);

// Get synthetic token mapping
function getTokenMapping(address sourceToken) external view returns (address);

// Get whitelisted tokens list
function getWhitelistedTokens() external view returns (address[] memory);
```

#### BalanceManager (Rari)

```solidity
// Check user balance of synthetic tokens
function balanceOf(address user, uint256 currencyId) external view returns (uint256);

// Withdraw synthetic tokens (burns and unlocks)
function withdraw(address user, uint256 currencyId, uint256 amount) external;
```

## Security Features

### 1. Token Whitelisting
- Only pre-approved tokens can be deposited
- Prevents malicious token deposits

### 2. Nonce Protection
- Each user has an incrementing nonce
- Prevents replay attacks

### 3. Message Verification
- Cross-chain messages are verified by origin and sender
- Prevents unauthorized minting

### 4. Ownership Controls
- ChainBalanceManager is owned by deployer
- Only owner can add tokens and set mappings

## Testing

### Manual Testing Commands

```bash
# Check token mapping
cast call $CBM_ADDRESS "getTokenMapping(address)(address)" $USDT_ADDRESS --rpc-url $RPC_URL

# Check if token is whitelisted
cast call $CBM_ADDRESS "isTokenWhitelisted(address)(bool)" $USDT_ADDRESS --rpc-url $RPC_URL

# Check user balance on Rari
cast call $BALANCE_MANAGER "balanceOf(address,uint256)(uint256)" $USER_ADDRESS $CURRENCY_ID --rpc-url https://rari.caff.testnet.espresso.network
```

### Test Scenarios

1. **Deposit Flow**: Deposit USDT on Appchain → Verify gsUSDT minted on Rari
2. **Cross-Chain Verification**: Deposit from multiple source chains to same recipient
3. **Token Variety**: Test all token types (USDT, WETH, WBTC)
4. **Error Handling**: Test with non-whitelisted tokens (should fail)

## Troubleshooting

### Common Issues

1. **Token Not Whitelisted**
   - Error: Reverts on deposit
   - Solution: Use `SetupTokenMappings.s.sol` to whitelist token

2. **Incorrect Mapping**
   - Error: Wrong synthetic token minted
   - Solution: Update mapping using `setTokenMapping()` function

3. **Insufficient Allowance**
   - Error: Transfer fails
   - Solution: Approve tokens before deposit

4. **Cross-Chain Message Failure**
   - Error: Synthetic tokens not minted
   - Solution: Check Hyperlane relayer status and gas prices

### Verification Commands

```bash
# Verify deployment configuration
cast call $CBM_ADDRESS "getHyperlaneConfig()(uint32,address)" --rpc-url $RPC_URL

# Check synthetic token supply
cast call $SYNTHETIC_TOKEN "totalSupply()(uint256)" --rpc-url https://rari.caff.testnet.espresso.network
```

## Configuration Files

All deployment addresses and configurations are stored in JSON files:

- `deployments/rari.json` - Rari testnet contracts
- `deployments/appchain.json` - Appchain testnet contracts  
- `deployments/rise-sepolia.json` - Rise Sepolia contracts
- `deployments/arbitrum-sepolia.json` - Arbitrum Sepolia contracts

These files are automatically updated by deployment scripts and read by configuration scripts to ensure consistency across the system.

## Next Steps

1. **Phase 1 Testing**: Test complete cross-chain deposit→mint→lock flow
2. **Phase 2 Deployment**: Deploy trading infrastructure (PoolManager, GTXRouter, OrderBook)
3. **Ownership Transfer**: Transfer BalanceManager ownership to PoolManager
4. **Pool Creation**: Create trading pools for synthetic token pairs
5. **Integration Testing**: Test complete trading flow with cross-chain deposits