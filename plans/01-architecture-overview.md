# GTX Platform Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────────┐
│                    OFF-CHAIN INDEXER                         │
│  • Snapshots Rari synthetic balances daily                  │
│  • Generates per-token Merkle trees                         │
│  • Posts roots to Base ($1/day)                             │
│  • Stores proofs in database                                │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Daily Merkle Roots (per token)
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              CHAIN BALANCE MANAGER (Base Chain)              │
│  • Holds real assets (USDC, WETH, WBTC, etc)               │
│  • Deploys 80% to ERC-4626 vaults (per token)              │
│  • Keeps 20% as hot reserve                                 │
│  • Verifies yield claims via Merkle proofs                  │
│  • Distributes yield from respective vaults                 │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ Bridge: Mint/Burn gTokens (Hyperlane)
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              BALANCE MANAGER (Rari Chain)                    │
│  • Mints/burns synthetic tokens (gUSDC, gWETH, gWBTC)       │
│  • Tracks synthetic balances for CLOB                       │
│  • Zero-sum trading (balances determine yield shares)       │
│  • Emits trade events (indexed off-chain)                   │
└─────────────────────────────────────────────────────────────┘
```

## Key Principles

1. **Pooled Liquidity**: All deposits of the same asset are pooled together
2. **Separate Concerns**: Base handles yield + real assets, Rari handles trading + synthetics
3. **Fair Distribution**: Yield distributed based on **current synthetic holdings** (not original deposits)
4. **Merkle Verification**: Daily snapshots prove user holdings without per-trade messages
5. **Dynamic Scalability**: Per-token Merkle trees - add new tokens without code changes
6. **No USD Conversion**: Each vault yields its underlying token (WETH → WETH, USDC → USDC)

## Supported Assets (Expandable)

- USDC (Aave lending - 7% APY)
- WETH (Lido staking - 3.5% APY)
- WBTC (Aave lending - 2% APY)
- USDT (Aave lending - 6% APY)
- _More assets can be added by deploying new vaults_

## Revenue Model

- Trading fees: 0.1-0.3% per trade on CLOB
- Yield management: 30% of all yield generated
- Cross-chain routing: 0.05% withdrawal fee (optional)
