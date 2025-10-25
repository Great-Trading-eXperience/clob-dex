# Yield Distribution System

## Overview

Yield is generated from ERC-4626 vaults on Base chain (one vault per token). Each vault yields its underlying token and distributes to current synthetic token holders on Rari.

## Yield Sources

### Per-Asset Vaults

```
USDC Vault → Aave Lending (7% APY)
├─ Deploys 80% of USDC deposits
├─ Auto-compounds via ERC-4626
└─ Share price increases over time

WETH Vault → Lido Staking (3.5% APY)
├─ Deploys 80% of WETH deposits
├─ Receives staking rewards
└─ Share price increases over time

WBTC Vault → Aave Lending (2% APY)
├─ Deploys 80% of WBTC deposits
├─ Earns interest
└─ Share price increases over time

... (additional vaults for new tokens)
```

### Per-Token Yield Distribution

**Each vault distributes its yield to holders of that token's synthetic version:**

```
Example Day 365:

Vault Performance:
├─ USDC Vault: 1000 USDC deposited → 70 USDC yield (7% APY)
├─ WETH Vault: 10 WETH deposited → 0.35 WETH yield (3.5% APY)
└─ WBTC Vault: 5 WBTC deposited → 0.1 WBTC yield (2% APY)

Synthetic Token Holders (from Rari snapshot):
├─ gUSDC holders:
│   • Alice: 500 gUSDC (50% of 1000 total)
│   • Bob: 500 gUSDC (50% of 1000 total)
│
├─ gWETH holders:
│   • Alice: 3 gWETH (30% of 10 total)
│   • Charlie: 7 gWETH (70% of 10 total)
│
└─ gWBTC holders:
    • Bob: 2 gWBTC (40% of 5 total)
    • Charlie: 3 gWBTC (60% of 5 total)

Yield Distribution:
├─ USDC Vault (70 USDC yield):
│   • Alice: 70 × 50% = 35 USDC ✅
│   • Bob: 70 × 50% = 35 USDC ✅
│
├─ WETH Vault (0.35 WETH yield):
│   • Alice: 0.35 × 30% = 0.105 WETH ✅
│   • Charlie: 0.35 × 70% = 0.245 WETH ✅
│
└─ WBTC Vault (0.1 WBTC yield):
    • Bob: 0.1 × 40% = 0.04 WBTC ✅
    • Charlie: 0.1 × 60% = 0.06 WBTC ✅
```

## Calculation Formula (Per-Token)

```solidity
// User's yield share for a specific token
userYieldShare = (vaultYield × userTokenBalance) / totalTokenSupply

// Example: Alice's WETH yield
// - WETH vault generated: 0.35 WETH
// - Alice holds: 3 gWETH
// - Total gWETH: 10
// - Alice's yield: (0.35 × 3) / 10 = 0.105 WETH

// No USD conversion needed! ✅
// Each token distributes its own yield
```

## Fairness Examples

### Example 1: Alice Trades USDC → ETH

```
Day 0: Deposits
├─ Alice deposits: 1000 USDC on Base
│   └─ Gets: 1000 gUSDC on Rari
├─ Bob deposits: 1 ETH on Base
│   └─ Gets: 1 gETH on Rari

Day 180: Alice trades on Rari
├─ Alice sells: 1000 gUSDC for 0.5 gETH
├─ Bob buys: 1000 gUSDC (pays 0.5 gETH)
└─ New holdings:
    • Alice: 0.5 gETH
    • Bob: 0.5 gETH + 1000 gUSDC

Day 365: Yield Distribution
├─ USDC Vault (Base): 70 USDC yield
│   └─ Who gets it? Bob! (he holds 1000 gUSDC now)
│       Bob receives: 70 USDC ✅
│
└─ ETH Vault (Base): 0.035 ETH yield
    └─ Who gets it? Alice + Bob! (they each hold 0.5 gETH)
        • Alice: 0.035 × (0.5/1) = 0.0175 ETH ✅
        • Bob: 0.035 × (0.5/1) = 0.0175 ETH ✅

This is FAIR because:
├─ Alice traded away her USDC → lost USDC yield rights
├─ Bob acquired USDC → gained USDC yield rights
└─ Yield follows current holdings, not original deposits ✅
```

### Example 2: Bob Sells BTC at a Loss

```
Day 0:
├─ Bob deposits: 1 BTC ($100K) on Base
└─ Gets: 1 gWBTC on Rari

Day 180: BTC crashes to $50K
├─ Bob panics and sells: 1 gWBTC → 50K gUSDC
└─ Bob now holds: 50K gUSDC (lost $50K value)

Day 365: Yield Distribution
├─ WBTC Vault: 0.02 BTC yield ($1K value)
│   └─ Who gets it? NOT Bob! (he sold his gWBTC)
│       Goes to whoever bought Bob's gWBTC ✅
│
└─ USDC Vault: 3.5K USDC yield
    └─ Bob gets his share of USDC yield
        Based on his 50K gUSDC holdings ✅

This is FAIR because:
├─ Bob made a trading decision to sell BTC
├─ He loses BTC yield rights when he sells
├─ He gains USDC yield rights when he buys
└─ Yield is not about original deposits, but current holdings ✅

Real-world parallel:
├─ Sell BTC on Binance → lose BTC staking rewards
├─ Same logic applies here (fair!) ✅
```

## Claiming Process

### Step 1: Check Claimable Yield (Per-Token)

```bash
GET /api/user/0xAlice.../claimable

Response:
{
  "user": "0xAlice...",
  "day": 365,
  "tokens": [
    {
      "token": "USDC",
      "address": "0x...",
      "userBalance": "500",
      "totalSupply": "10000",
      "share": "5%",
      "vaultYield": "700",
      "userYield": "35",
      "claimed": "10",
      "newClaimable": "25"
    },
    {
      "token": "WETH",
      "address": "0x...",
      "userBalance": "0.3",
      "totalSupply": "10",
      "share": "3%",
      "vaultYield": "0.35",
      "userYield": "0.0105",
      "claimed": "0",
      "newClaimable": "0.0105"
    }
  ]
}
```

### Step 2: Get Merkle Proofs (Per-Token)

```bash
GET /api/proofs/0xAlice.../day/365

Response:
{
  "day": 365,
  "user": "0xAlice...",
  "proofs": [
    {
      "token": "USDC",
      "balance": "500",
      "proof": ["0xabc...", "0xdef..."]
    },
    {
      "token": "WETH",
      "balance": "0.3",
      "proof": ["0x123...", "0x456..."]
    }
  ]
}
```

### Step 3: Submit Claims (Per-Token or Batch)

```solidity
// Option A: Claim single token
chainBalanceManager.claimYield(
    365,                // day
    USDC_ADDRESS,       // token
    500e6,              // userBalance
    usdcMerkleProof     // proof
);

// Option B: Batch claim all tokens
ClaimProof[] memory proofs = [...];
chainBalanceManager.claimYieldBatch(365, proofs);
```

### Step 4: Receive Yield (Per-Token)

```
Smart contract (for each token):
1. Verifies Merkle proof for that token ✓
2. Calculates yield share: (vaultYield × userBalance) / totalSupply
3. Withdraws from specific vault (e.g., USDC vault)
4. Sends token to user (e.g., 35 USDC)
5. Updates userClaimedYield[user][token]

Example:
├─ Alice claims USDC: receives 35 USDC
├─ Alice claims WETH: receives 0.0105 WETH
└─ Each token claimed separately or in batch
```

## Withdrawal in Mixed Assets

Users can choose to receive yield in:

**Option A: Single Asset (Simplest)**

```solidity
function claimYieldInAsset(
    uint256 day,
    uint256 userValueUSD,
    bytes32[] calldata merkleProof,
    address preferredAsset  // e.g., USDC
) external {
    // Calculate yield
    uint256 yieldAmount = _calculateYield(...);

    // Withdraw from vaults and convert to preferred asset
    _withdrawAndConvert(yieldAmount, preferredAsset);

    // Transfer to user
    IERC20(preferredAsset).transfer(msg.sender, yieldAmount);
}
```

**Option B: Proportional Mix**

```solidity
function claimYieldMixed(
    uint256 day,
    uint256 userValueUSD,
    bytes32[] calldata merkleProof
) external {
    // Withdraw proportionally from each vault
    // Send mix of assets to user

    // Example: $100 yield from 3 vaults
    ├─ 40% from USDC vault → 40 USDC
    ├─ 35% from ETH vault → 0.0175 ETH
    └─ 25% from WBTC vault → 0.000625 WBTC
}
```

## Anti-Double-Claim Protection

```solidity
mapping(address => uint256) public totalYieldClaimed;

function claimYield(...) external {
    // Calculate cumulative yield user has earned
    uint256 cumulativeYield = _calculateTotalYield(msg.sender);

    // Calculate new yield
    uint256 alreadyClaimed = totalYieldClaimed[msg.sender];
    uint256 newYield = cumulativeYield - alreadyClaimed;

    require(newYield > 0, "Nothing new to claim");

    // Distribute new yield only
    _distribute(msg.sender, newYield);

    // Update cumulative claimed
    totalYieldClaimed[msg.sender] = cumulativeYield;
}
```

## Revenue Distribution

```
Example: $1M TVL, $60k annual yield

Revenue Split:
├─ Users (70%): $42,000
│   └─ Distributed proportionally to all holders
│
└─ Protocol (30%): $18,000
    ├─ Operations: 40% ($7,200)
    ├─ Development: 30% ($5,400)
    ├─ Treasury: 20% ($3,600)
    └─ Team: 10% ($1,800)
```

## Gas Optimization

```
Batch Claiming:
├─ Users accumulate yield over time
├─ Claim once per week/month to save gas
└─ Each claim costs ~$2-5

Recommended claiming frequency:
├─ < $100 claimable: Wait
├─ $100-1000: Claim monthly
└─ > $1000: Claim weekly
```

## Future Enhancements

1. **Auto-compounding**: Automatically reinvest claimed yield
2. **Yield swapping**: Swap yield to preferred token before claiming
3. **Gasless claiming**: Use meta-transactions or relayers
4. **Yield streaming**: Claim yield continuously instead of in batches
