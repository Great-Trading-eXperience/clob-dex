# Merkle Tree System

## Overview

The platform uses **daily per-token Merkle tree snapshots** to efficiently track user holdings. Each token has its own Merkle tree, allowing infinite scalability without code changes.

## How It Works

### Daily Process (Per-Token Trees)

```
1. Indexer reads synthetic balances from Rari
   ├─ Alice: 500 gUSDC, 0.3 gWETH, 0.01 gWBTC
   ├─ Bob: 2000 gUSDC, 0 gWETH, 0.1 gWBTC
   └─ Charlie: 0 gUSDC, 1.5 gWETH, 0.05 gWBTC

2. Build separate Merkle tree for EACH token

   USDC Tree:
   ├─ Leaf₁ = keccak256(abi.encode(Alice, 500))
   ├─ Leaf₂ = keccak256(abi.encode(Bob, 2000))
   └─ Root_USDC = 0xABC...

   WETH Tree:
   ├─ Leaf₁ = keccak256(abi.encode(Alice, 0.3))
   ├─ Leaf₂ = keccak256(abi.encode(Charlie, 1.5))
   └─ Root_WETH = 0xDEF...

   WBTC Tree:
   ├─ Leaf₁ = keccak256(abi.encode(Alice, 0.01))
   ├─ Leaf₂ = keccak256(abi.encode(Bob, 0.1))
   ├─ Leaf₃ = keccak256(abi.encode(Charlie, 0.05))
   └─ Root_WBTC = 0xGHI...

3. Post all roots to Base chain (ONE transaction)
   └─ Cost: ~$1 regardless of number of users or tokens
```

### Leaf Structure (Per-Token)

```solidity
// Simple: Each token tree has leaves with user + balance
struct MerkleLeaf {
    address user;     // User's address
    uint256 balance;  // User's balance of THIS token
}

// Encoded as (same for all tokens):
bytes32 leaf = keccak256(abi.encodePacked(user, balance));
```

**Key Insight**: One tree per token = infinite scalability!

- ✅ Simple: `hash(user, balance)` for ALL tokens
- ✅ DRY: Same leaf structure for USDC, WETH, WBTC, LINK, etc.
- ✅ Adding new tokens = new tree, ZERO code changes

## Scalability

### Adding New Tokens (Dynamic Scalability)

```
Day 0: Support 3 tokens
├─ USDC Tree: hash(user, usdcBalance)
├─ WETH Tree: hash(user, wethBalance)
└─ WBTC Tree: hash(user, wbtcBalance)
    Cost: $1/day

Day 100: Add LINK (just deploy vault + configure!)
├─ USDC Tree: hash(user, usdcBalance)  ← Same
├─ WETH Tree: hash(user, wethBalance)  ← Same
├─ WBTC Tree: hash(user, wbtcBalance)  ← Same
└─ LINK Tree: hash(user, linkBalance)  ← NEW! Auto-included
    Cost: $1/day  ← STILL $1!

Day 365: Support 50 tokens
├─ 50 separate trees
├─ Same leaf structure for all: hash(user, balance)
├─ Indexer automatically includes all tokens
└─ No contract code changes needed!
    Cost: $1/day  ← ALWAYS $1! ✅
```

### User Growth Scalability

| Users     | Merkle Tree Depth | Proof Size (hashes) | Gas Cost  |
| --------- | ----------------- | ------------------- | --------- |
| 100       | 7                 | 7                   | ~50k gas  |
| 1,000     | 10                | 10                  | ~65k gas  |
| 10,000    | 14                | 14                  | ~85k gas  |
| 100,000   | 17                | 17                  | ~100k gas |
| 1,000,000 | 20                | 20                  | ~120k gas |

**Cost to post root**: Always ~$1 (one transaction)
**Cost to verify proof**: ~$2-5 per user (they pay when claiming)

## Merkle Proof Verification

### Smart Contract (Per-Token)

```solidity
function claimYield(
    uint256 day,
    address token,           // Which token to claim
    uint256 userBalance,     // User's balance from snapshot
    bytes32[] calldata merkleProof
) external {
    // 1. Get the Merkle root for this token on this day
    bytes32 root = snapshotMerkleRoots[day][token];
    require(root != bytes32(0), "No snapshot");

    // 2. Reconstruct leaf
    bytes32 leaf = keccak256(abi.encodePacked(msg.sender, userBalance));

    // 3. Verify proof
    require(
        MerkleProof.verify(merkleProof, root, leaf),
        "Invalid proof"
    );

    // 4. Calculate yield share for THIS token
    uint256 totalSupply = snapshotTotalSupply[day][token];
    uint256 vaultYield = snapshotCumulativeYield[day][token];
    uint256 userYield = (vaultYield * userBalance) / totalSupply;

    // 5. Withdraw from vault and send
    _withdrawYield(token, userYield, msg.sender);
}
```

### User Flow (Per-Token Claims)

```
1. User wants to claim WETH yield
   └─ Queries indexer: GET /proof/alice/day/365/weth

2. Indexer returns:
   {
     "user": "0xAlice...",
     "day": 365,
     "token": "0xWETH...",
     "userBalance": "0.3",  // Alice's gWETH balance
     "merkleProof": [
       "0xabc...",
       "0xdef..."
     ],
     "totalSupply": "10.5",   // Total gWETH
     "estimatedYield": "0.001 WETH"
   }

3. User submits to Base chain:
   └─ claimYield(365, WETH_ADDRESS, 0.3e18, merkleProof)

4. Base verifies proof and pays 0.001 WETH yield

5. User can claim other tokens separately:
   └─ claimYield(365, USDC_ADDRESS, 500e6, usdcProof)
   └─ claimYield(365, WBTC_ADDRESS, 0.01e8, wbtcProof)
```

## Example: Multi-Token Scenario

### Setup

```
Alice's holdings on Rari (synthetic tokens):
├─ 500 gUSDC
├─ 0.3 gWETH
├─ 0.01 gWBTC
├─ 200 gUSDT
└─ 300 gDAI
```

### Merkle Leaves (Per-Token)

```solidity
// USDC Tree - Alice's leaf:
bytes32 aliceUSDCLeaf = keccak256(abi.encodePacked(
    0xAlice,  // Address
    500e6     // 500 gUSDC
));

// WETH Tree - Alice's leaf:
bytes32 aliceWETHLeaf = keccak256(abi.encodePacked(
    0xAlice,
    0.3e18    // 0.3 gWETH
));

// WBTC Tree - Alice's leaf:
bytes32 aliceWBTCLeaf = keccak256(abi.encodePacked(
    0xAlice,
    0.01e8    // 0.01 gWBTC
));

// Same pattern for USDT, DAI, etc. ✅
// DRY: Exact same code for ALL tokens!
```

### Adding New Token (e.g., LINK)

```
Day 100: Admin deploys LINK vault

1. Deploy LINK ERC-4626 vault on Base
2. Configure: chainBalanceManager.setVault(LINK, linkVault)
3. Indexer automatically detects LINK from tokenList[]
4. Next snapshot includes LINK tree!

Alice trades to get 50 gLINK:

LINK Tree (NEW):
├─ Leaf₁ = keccak256(abi.encodePacked(Alice, 50))
├─ Leaf₂ = keccak256(abi.encodePacked(Bob, 100))
└─ Root_LINK = 0xJKL...

Zero changes needed to:
├─ Contract code ✅
├─ Indexer code ✅  (reads tokenList dynamically)
├─ Leaf structure ✅  (same hash(user, balance))
└─ API ✅  (generic /proof/:user/:day/:token)

Cost: Still $1/day! ✅
```

## Cost Analysis

### Traditional Approach (Per-Trade Messages)

```
Alice makes 10 trades per day
├─ Trade 1: gUSDC → gETH ($1 message)
├─ Trade 2: gETH → gWBTC ($1 message)
├─ ... (8 more trades)
└─ Total: $10/day for ONE user

1000 active traders × 10 trades = $10,000/day ❌
```

### Merkle Approach

```
All users trade as much as they want
├─ Trade 1: Free (local on Anvil)
├─ Trade 2: Free
├─ ... (unlimited trades)
└─ End of day: $1 snapshot for ALL users

1000 active traders × unlimited trades = $1/day ✅

Savings: 99.99%! 🎉
```

## Security Considerations

### Attack Vectors

**1. Fake Merkle Proof**

```
Attack: User tries to submit fake proof
Defense: Cryptographic verification ensures proof must match root
Result: Transaction reverts ✅
```

**2. Malicious Indexer**

```
Attack: Indexer posts wrong Merkle root
Defense:
├─ Multi-indexer consensus (2-of-3)
├─ Challenge period (24h dispute window)
├─ Bond/slash mechanism
└─ Community can run own indexer
Result: Attack detected and prevented ✅
```

**3. Stale Snapshot**

```
Attack: User claims using old snapshot when their balance was higher
Defense:
├─ Track cumulative yield claimed
├─ Only pay difference since last claim
├─ Can't claim more than total earned
Result: Attack has no benefit ✅
```

## API Endpoints

### Indexer API (Per-Token)

```
GET /proof/:user/:day/:token
└─ Returns Merkle proof for specific token on specific day

GET /proofs/:user/:day
└─ Returns all proofs for user (all tokens) for batch claiming

GET /latest-snapshot
└─ Returns most recent snapshot (all token roots)

GET /user/:address/holdings
└─ Returns current synthetic holdings per token

GET /user/:address/claimable
└─ Returns claimable yield for ALL tokens

GET /platform/stats
└─ Returns TVL, yield per vault, etc.

Example response from GET /user/0xAlice/claimable:
{
  "user": "0xAlice...",
  "day": 365,
  "tokens": [
    { "token": "USDC", "claimable": "3.5", "usd": "3.5" },
    { "token": "WETH", "claimable": "0.001", "usd": "2.0" },
    { "token": "WBTC", "claimable": "0.00002", "usd": "0.8" }
  ],
  "totalUSD": "6.3"
}
```

## Future Enhancements

1. **ZK Proofs**: Replace Merkle proofs with ZK proofs for privacy
2. **Rollup Integration**: Move snapshot generation to ZK rollup
3. **Optimistic Verification**: Challenge-based system instead of Merkle proofs
4. **Cross-Chain Snapshots**: Aggregate holdings across multiple chains

## References

- [Merkle Trees Explained](https://brilliant.org/wiki/merkle-tree/)
- [EIP-1186: Merkle Proofs](https://eips.ethereum.org/EIPS/eip-1186)
- [OpenZeppelin MerkleProof](https://docs.openzeppelin.com/contracts/4.x/api/utils#MerkleProof)
