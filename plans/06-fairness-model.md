# Fairness Model: Current Holdings vs. Original Deposits

## Overview

The GTX yield distribution model is based on **current synthetic holdings**, not original deposits. This document explains why this approach is fair and aligns with how traditional exchanges work.

## The Core Question

**Should yield follow what you deposited, or what you currently hold?**

Answer: **What you currently hold** (current synthetic balances on Rari).

## Why Current Holdings?

### Example 1: Bob's Trading Journey

```
Day 0: Bob deposits 1 BTC ($100,000)
├─ ChainBalanceManager locks 1 BTC on Base
├─ BalanceManager mints 1 gBTC on Rari
└─ Bob now holds: 1 gBTC

Day 100: Bob trades BTC → USDT
├─ Bob sells 1 gBTC for 100,000 gUSDT on Rari CLOB
├─ Alice buys 1 gBTC (pays 100,000 gUSDT)
└─ New holdings:
    • Bob: 100,000 gUSDT, 0 gBTC
    • Alice: 1 gBTC, 0 gUSDT

Day 365: Yield Distribution
├─ BTC Vault (Base): Generated 0.02 BTC yield
│   Question: Who should get this?
│
│   Option A: Bob (original depositor)
│   ├─ Problem: Bob sold his BTC position!
│   ├─ He doesn't own gBTC anymore
│   └─ Giving him BTC yield would be UNFAIR to Alice
│
│   Option B: Alice (current holder) ✅
│   ├─ Alice currently holds 1 gBTC
│   ├─ She has economic exposure to BTC
│   └─ She should get BTC yield! FAIR ✅
│
└─ USDT Vault (Base): Generated 6,000 USDT yield
    ├─ Bob currently holds 100,000 gUSDT
    ├─ He has economic exposure to USDT
    └─ He should get USDT yield! FAIR ✅
```

**Conclusion**: Yield follows current holdings, not original deposits.

## Comparison to Centralized Exchanges

### Binance/Coinbase Model

```
User deposits 1 BTC → Earns BTC staking rewards

User trades BTC → USDT:
├─ LOSES BTC staking rewards immediately
└─ GAINS USDT lending APY immediately

GTX follows the same logic! ✅
```

### Why This is Fair

| Scenario | CEX Behavior | GTX Behavior | Fair? |
|----------|--------------|--------------|-------|
| Hold BTC | Earn BTC yield | Earn BTC yield | ✅ Same |
| Trade BTC→USDT | Lose BTC yield, gain USDT yield | Lose BTC yield, gain USDT yield | ✅ Same |
| Sell at loss | Still lose yield rights | Still lose yield rights | ✅ Same |

**GTX behaves exactly like traditional exchanges!**

## Alternative (Unfair) Model

### Original-Deposit-Based Yield ❌

```
Day 0:
├─ Alice deposits 1000 USDC (7% APY vault)
├─ Bob deposits 1000 USDT (6% APY vault)

Day 100: They trade
├─ Alice trades 1000 gUSDC → 1000 gUSDT
├─ Bob trades 1000 gUSDT → 1000 gUSDC
└─ Holdings swapped!

Day 365: Yield Distribution (if based on original deposits)
├─ USDC Vault: 70 USDC yield
│   └─ Gives to Alice (original depositor)
│       Problem: Alice doesn't own USDC anymore!
│       She holds USDT, but gets USDC yield ❌
│
└─ USDT Vault: 60 USDT yield
    └─ Gives to Bob (original depositor)
        Problem: Bob doesn't own USDT anymore!
        He holds USDC, but gets USDT yield ❌

This is UNFAIR and doesn't make sense! ❌
```

### Problems with Original-Deposit Model

1. **Mismatch**: You receive yield for assets you don't own
2. **No Incentive to Trade**: Trading loses you yield rights unfairly
3. **Complexity**: Need to track original deposits forever
4. **Not Tradeable**: Can't transfer yield rights when you trade
5. **Doesn't Match CEXs**: Traditional exchanges don't work this way

## Real-World Scenarios

### Scenario 1: Day Trader

```
Alice is an active trader:
├─ Day 1: Holds gUSDC → earns USDC yield
├─ Day 2: Trades to gETH → earns ETH yield
├─ Day 3: Trades to gWBTC → earns WBTC yield
├─ Day 4: Trades back to gUSDC → earns USDC yield

Fair behavior:
├─ Each day, she earns yield on what she currently holds
└─ Aligns with her trading strategy ✅

Unfair (original deposit) behavior:
├─ She always earns USDC yield (original deposit)
├─ Even when she holds ETH or WBTC
└─ Doesn't align with her positions ❌
```

### Scenario 2: Market Crash

```
Bob holds 1 gBTC worth $100,000

Market crashes: BTC drops to $50,000

Bob panics and sells: 1 gBTC → 50,000 gUSDC

Day 365: BTC recovers to $100,000
├─ BTC vault generated 2% yield = $2,000 worth
│
├─ Current holdings model:
│   └─ Bob doesn't get BTC yield (he sold!)
│       Goes to whoever holds gBTC now ✅
│       FAIR: Bob made a trading decision
│
└─ Original deposit model:
    └─ Bob gets BTC yield (original depositor)
        Even though he panic-sold ❌
        UNFAIR: Rewards bad trading decisions
```

### Scenario 3: Yield Optimization

```
Alice wants to maximize yield:

She notices:
├─ USDC vault: 7% APY
├─ WBTC vault: 2% APY

Smart strategy:
├─ Deposit to USDC vault (high APY)
├─ Trade on Rari: gUSDC ↔ gWBTC as needed
├─ Keep majority in gUSDC to earn 7% yield
└─ This is FAIR and encouraged! ✅

With original deposit model:
├─ Once she deposits USDC, she's locked into 7% forever
├─ Even if she trades to WBTC
└─ Less flexible, doesn't reward optimization ❌
```

## The Philosophical Argument

### Property Rights

```
When you sell an asset, you sell:
1. The asset itself ✅
2. Economic exposure to that asset ✅
3. Future yield/income from that asset ✅

Example (real estate):
├─ You own a rental property earning $1,000/month
├─ You sell the property
├─ You NO LONGER get the $1,000/month rent
└─ New owner gets the rent ✅

Same logic applies to crypto yield!
```

### Economic Exposure

```
Yield should align with economic exposure:

If you hold gBTC:
├─ You have BTC price exposure
├─ You should have BTC yield exposure
└─ Makes sense! ✅

If you hold gUSDC:
├─ You have stable USD exposure
├─ You should have USDC yield exposure
└─ Makes sense! ✅

If you deposited BTC but now hold USDC:
├─ You have USD exposure (not BTC)
├─ You should have USDC yield (not BTC)
└─ Makes sense! ✅
```

## Edge Cases

### What if someone holds 0 tokens?

```
Alice sells all her tokens: 0 gUSDC, 0 gWETH, 0 gWBTC

Yield distribution:
├─ Alice receives: $0 yield (she holds nothing)
└─ FAIR: No holdings = no yield ✅
```

### What about trading fees?

```
Alice buys gBTC, pays 0.1% trading fee

Later:
├─ Alice sells gBTC, pays 0.1% trading fee
├─ Alice loses 0.2% total to fees
├─ But she still earned BTC yield while holding
└─ FAIR: Trading has costs, holding has rewards ✅
```

### What if yield is very small?

```
Bob holds 10 gUSDC (small position)
USDC vault generates 0.7 USDC total yield
Total supply: 10,000 gUSDC

Bob's share: (0.7 × 10) / 10,000 = 0.0007 USDC

Bob receives: 0.0007 USDC ✅
├─ Small holding = small yield
└─ FAIR: Proportional to holdings ✅
```

## Why Not Pool All Yield?

### Pooled Yield Problem ❌

```
Idea: Pool all yield together, distribute by USD value

Example:
├─ Alice deposits 1000 USDC (7% APY) → $70 yield
├─ Bob deposits $1000 worth of WBTC (2% APY) → $20 yield
├─ Total yield: $90

Pooled distribution:
├─ Alice gets: $45 (50% of pool)
├─ Bob gets: $45 (50% of pool)

Problem: Alice deposited high-APY asset, but gets same as Bob!
├─ Alice contributed $70 but gets $45 (loses $25)
├─ Bob contributed $20 but gets $45 (gains $25)
└─ UNFAIR: Penalizes depositing high-APY assets ❌

Per-token distribution:
├─ Alice gets: $70 USDC yield (from USDC vault)
├─ Bob gets: $20 WBTC yield (from WBTC vault)
└─ FAIR: Each person gets what their deposit earned ✅
```

## Incentive Alignment

### What behavior does this model encourage?

```
✅ GOOD Incentives:
├─ Deposit high-APY assets (you keep high yield!)
├─ Hold tokens long-term (accumulate yield)
├─ Trade strategically (optimize yield)
└─ Participate in liquidity provision

❌ BAD Incentives (avoided):
├─ Gaming the system (can't claim yield you don't deserve)
├─ Depositing low-APY then trading (yield follows holdings)
└─ Complexity/exploits (simple pro-rata model)
```

## Summary: The Fairness Checklist

| Question | Answer | Fair? |
|----------|--------|-------|
| Should you earn yield on assets you don't own? | No | ✅ |
| Should trading change your yield rights? | Yes | ✅ |
| Should yield follow economic exposure? | Yes | ✅ |
| Should it match how CEXs work? | Yes | ✅ |
| Should it be simple and transparent? | Yes | ✅ |
| Should it reward high-APY deposits? | Yes | ✅ |
| Should it penalize trading? | No | ✅ |

**All checkboxes passed! Current holdings model is fair! ✅**

## Mathematical Proof of Fairness

### Claim: Total yield distributed = Total yield generated

```
Proof:

For each token T:
├─ Vault generates: Y_T yield
├─ Total synthetic supply: S_T
├─ User i holds: B_i,T tokens
│
├─ User i's yield: (Y_T × B_i,T) / S_T
│
└─ Sum over all users:
    Σ(Y_T × B_i,T / S_T) = Y_T × Σ(B_i,T) / S_T
                          = Y_T × S_T / S_T
                          = Y_T ✅

QED: All vault yield is distributed, nothing lost!
```

### Claim: No user can claim yield they didn't earn

```
Proof:

User i can only claim yield for token T if:
1. They have valid Merkle proof (cryptographically verified)
2. Proof shows B_i,T > 0 (they hold some tokens)
3. Yield = (Y_T × B_i,T) / S_T (proportional)

If B_i,T = 0:
├─ Yield = (Y_T × 0) / S_T = 0
└─ Can't claim anything ✅

If they forge proof:
├─ Merkle verification fails
└─ Transaction reverts ✅

QED: Impossible to claim unearned yield!
```

## Final Verdict

**The current-holdings-based yield model is:**
- ✅ Fair to all participants
- ✅ Aligned with CEX behavior
- ✅ Mathematically sound
- ✅ Economically logical
- ✅ Simple to understand
- ✅ Easy to implement
- ✅ Impossible to game

**This is the RIGHT approach! 🎯**
