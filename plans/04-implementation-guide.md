# Implementation Guide

## Phase 1: MVP (Hackathon)

### Core Contracts

**1. ChainBalanceManager.sol** (Base chain)

```solidity
// Key functions (DYNAMIC):
- deposit(asset, amount) // Auto-deploys to vault
- withdraw(asset, amount, proof)
- claimYield(day, token, userBalance, merkleProof) // Per-token
- claimYieldBatch(day, ClaimProof[] proofs) // Batch claim
- updateDailySnapshot(day, TokenSnapshot[] snapshots) // Dynamic array!
- setVault(token, vault) // Add new vaults dynamically
```

**2. BalanceManager.sol** (Rari chain)

```solidity
// Key functions (already exists):
- mint(user, asset, amount) onlyBridge
- burn(user, asset, amount) onlyBridge
- getBalance(user, asset) view // Used by indexer
- depositLocal(token, amount, recipient) // Local deposits
```

**3. CLOB.sol** (Anvil chain)

```solidity
// Key functions:
- placeOrder(fromAsset, toAsset, amount, price)
- cancelOrder(orderId)
- matchOrders()
```

### Off-Chain Indexer (Dynamic & DRY)

```typescript
// yield-bot/src/snapshot.ts
import { ethers } from "ethers";
import { MerkleTree } from "merkletreejs";

// DRY: Generic function for ANY token
async function buildTokenTree(token: string) {
  const holders = await getAllHolders(token);
  const balances = await Promise.all(
    holders.map(user => balanceManager.getBalance(user, token))
  );

  const leaves = balances.map((bal, i) =>
    ethers.utils.solidityKeccak256(
      ['address', 'uint256'],
      [holders[i], bal]
    )
  );

  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  return { token, root: tree.getHexRoot(), totalSupply, tree };
}

// Daily snapshot job (DYNAMIC)
async function dailySnapshot() {
  // 1. Get ALL tokens dynamically
  const tokens = await chainBalanceManager.getWhitelistedTokens();

  // 2. Build tree for each token (DRY - same code!)
  const snapshots = await Promise.all(
    tokens.map(token => buildTokenTree(token))
  );

  // 3. Post all roots in ONE transaction
  await chainBalanceManager.updateDailySnapshot(day, snapshots);
}

// API endpoints (per-token)
app.get("/proof/:user/:day/:token", getProof);
app.get("/proofs/:user/:day", getAllProofs);
app.get("/claimable/:user", getClaimableYield);
```

### Deployment Checklist

- [ ] Deploy ERC-4626 vaults (USDC, WETH, WBTC)
- [ ] Deploy ChainBalanceManager on Base
- [ ] Deploy BalanceManager + CLOB on Anvil
- [ ] Set up bridge (LayerZero/CCIP)
- [ ] Deploy indexer server
- [ ] Set up daily cron job for snapshots
- [ ] Create API for proof generation
- [ ] Build frontend interface

### Testing Scenarios

```
Scenario 1: Single asset deposit & withdraw
├─ Alice deposits 1000 USDC
├─ Waits 1 day
├─ Withdraws 1000 USDC
└─ ✓ Success

Scenario 2: Trade and withdraw different asset
├─ Alice deposits 1000 USDC
├─ Trades to 0.5 ETH
├─ Withdraws 0.5 ETH
└─ ✓ Success

Scenario 3: Yield claim after trading
├─ Alice deposits 1000 USDC
├─ Trades to 0.5 ETH
├─ Waits 1 year
├─ Claims yield (gets USDC or ETH)
└─ ✓ Success

Scenario 4: Multi-user yield distribution
├─ Alice deposits 1000 USDC
├─ Bob deposits 1 ETH
├─ Both trade actively
├─ After 1 year, both claim
├─ Verify: Yield distributed proportionally
└─ ✓ Success
```

## Phase 2: Production

### Security Audits

1. **Smart contract audit** ($50k-100k)

   - ChainBalanceManager
   - Bridge contracts
   - Vault strategies

2. **Indexer security review**
   - Multi-indexer consensus
   - Challenge mechanism
   - Slashing conditions

### Decentralization

```
Indexer Network:
├─ Phase 1: Single trusted indexer
├─ Phase 2: 3 indexers (2-of-3 consensus)
└─ Phase 3: Permissionless indexer network

Bridge:
├─ Phase 1: LayerZero/CCIP
└─ Phase 2: Custom bridge with fraud proofs

Governance:
├─ Phase 1: Multi-sig
└─ Phase 2: DAO with token voting
```

### Multi-Chain Expansion

```
Supported Source Chains:
├─ Base ✅
├─ Arbitrum (add USDC/ETH vaults)
├─ Optimism (add USDC/ETH vaults)
├─ Polygon (add USDC/MATIC vaults)
└─ ... (any EVM chain)

Host Chain:
└─ Anvil (or migrate to dedicated app-chain)
```

### Monitoring & Analytics

```
Metrics to Track:
├─ Total Value Locked (TVL)
├─ Daily trading volume
├─ Yield generated per vault
├─ User count & retention
├─ Gas costs (indexer, users)
├─ Slippage & liquidation events
└─ Revenue (fees + yield cut)

Dashboards:
├─ Dune Analytics
├─ The Graph
└─ Custom dashboard
```

## Gas Cost Estimates

```
Base Chain (Optimistic L2):
├─ Deposit: $0.10-0.50
├─ Withdraw: $0.50-2.00
├─ Claim yield: $0.50-2.00
└─ Daily snapshot: $0.50-1.00

Anvil Chain:
├─ Trades: $0.01-0.05 (low gas)
├─ Mint/burn: Called by bridge
└─ User doesn't pay directly

Total user cost per month:
└─ ~$5-10 (1 deposit, some trades, 1 withdraw, 1 claim)
```

## API Documentation

### Endpoints

```
Base URL: https://api.gtx.exchange

Authentication: None (public read endpoints)

GET /health
└─ Returns: { status: "ok", version: "1.0" }

GET /snapshot/latest
└─ Returns: { day, root, totalValue, timestamp }

GET /user/:address/holdings
└─ Returns: { assets: {...}, totalUSD, lastUpdated }

GET /user/:address/claimable
└─ Returns: { claimable, breakdown, day }

GET /proof/:address/:day
└─ Returns: { proof: [...], value, day }

GET /platform/stats
└─ Returns: { tvl, users, volume24h, yieldGenerated }

GET /vaults
└─ Returns: [ { asset, apy, deployed, available } ]
```

## Troubleshooting

### Common Issues

**Issue**: Merkle proof verification fails

```
Solution:
1. Check that snapshot day exists
2. Verify user value is correct
3. Ensure proof array is in correct order
4. Check that root hash matches on-chain
```

**Issue**: Withdrawal fails - insufficient liquidity

```
Solution:
1. Check hot reserve balance
2. Try withdrawing different asset
3. Wait for rebalancing
4. Or initiate manual rebalancing
```

**Issue**: Yield claim reverts - "nothing to claim"

```
Solution:
1. Check totalYieldClaimed[user]
2. Verify time passed since last claim
3. Ensure vaults have generated yield
4. Check that snapshot is recent
```

## Support & Resources

- Documentation: https://docs.gtx.exchange
- GitHub: https://github.com/gtx-exchange
- Discord: https://discord.gg/gtx
- Twitter: https://twitter.com/gtx_exchange
