# GTX Yield System - Deployment Guide

## 📋 Overview

This guide walks through deploying the complete GTX yield distribution system, from smart contracts to off-chain components.

## ✅ Prerequisites

### 1. Environment Setup

```bash
# .env file
DEPLOYER_PRIVATE_KEY=your_private_key_here
RPC_URL_BASE=https://mainnet.base.org
RPC_URL_RARI=https://rari-testnet.rpc.caldera.xyz/http
ETHERSCAN_API_KEY=your_etherscan_api_key
```

### 2. Dependencies Installed

```bash
forge install
npm install # For off-chain indexer (separate repo)
```

### 3. Git Conflicts Resolved

All git merge conflicts have been fixed. Verify with:
```bash
git status # Should show no conflicts
forge build # Should compile without errors
```

---

## 🚀 Phase 1: Smart Contract Deployment

### Step 1: Deploy VaultFactory

The VaultFactory is a single contract that deploys ERC-4626 vaults for all tokens.

```bash
# Deploy to Base Sepolia (testnet)
forge script script/yield/DeployVaultFactory.s.sol \
  --rpc-url $RPC_URL_BASE \
  --broadcast \
  --verify

# Output example:
# VAULT_FACTORY=0x1234...
```

**What it does:**
- Deploys `VaultFactory` contract
- Owner can deploy vaults for any ERC-20 token
- Follows DRY principle: same factory for all vaults

### Step 2: Deploy Vaults for All Tokens

Deploy ERC-4626 vaults for USDC, WETH, WBTC, USDT:

```bash
# Option A: Deploy individually
forge script script/yield/DeployVaults.s.sol \
  --rpc-url $RPC_URL_BASE \
  --broadcast \
  --verify

# Option B: Batch deploy (more gas efficient)
forge script script/yield/DeployVaults.s.sol \
  --sig "runBatch()" \
  --rpc-url $RPC_URL_BASE \
  --broadcast \
  --verify

# Output:
# VAULT_USDC=0x...
# VAULT_WETH=0x...
# VAULT_WBTC=0x...
# VAULT_USDT=0x...
```

**What it does:**
- Deploys SimpleERC4626Vault for each token
- Vaults are ERC-4626 compliant
- Can be replaced with real yield strategies (Aave, Compound) later

### Step 3: Configure ChainBalanceManager with Vaults

Connect vaults to ChainBalanceManager:

```bash
forge script script/yield/ConfigureVaults.s.sol \
  --rpc-url $RPC_URL_BASE \
  --broadcast

# What happens:
# 1. Sets vault for USDC, WETH, WBTC, USDT
# 2. Sets vault ratio to 80% (8000 basis points)
# 3. Verifies configuration
```

**Verify:**
```bash
# Check vault configured for USDC
cast call $CHAIN_BALANCE_MANAGER "getVault(address)(address)" $USDC

# Check vault ratio
cast call $CHAIN_BALANCE_MANAGER "getVaultRatio()(uint256)"
# Should return: 8000 (80%)
```

---

## 🧪 Phase 2: Testing

### Step 1: Run Unit Tests

```bash
# Run all yield tests
forge test --match-contract ChainBalanceManagerYieldTest -vv

# Run specific test
forge test --match-test test_DepositWithVaultIntegration -vvv

# With gas reporting
forge test --match-contract ChainBalanceManagerYieldTest --gas-report
```

**Expected Output:**
```
Running 20 tests for test/core/ChainBalanceManagerYieldTest.t.sol

[PASS] test_SetVault() (gas: 45231)
[PASS] test_DepositWithVaultIntegration() (gas: 234567)
[PASS] test_ClaimYieldWithValidProof() (gas: 287654)
[PASS] test_FairnessModel_TradeAwayLoseYield() (gas: 298765)
...

Test result: ok. 20 passed; 0 failed
```

### Step 2: Integration Test

Test full flow: deposit → vault deployment → yield generation → claiming

```bash
# 1. Deploy everything to testnet
forge script script/yield/DeployVaultFactory.s.sol --broadcast --rpc-url $RPC_URL_BASE
forge script script/yield/DeployVaults.s.sol --broadcast --rpc-url $RPC_URL_BASE
forge script script/yield/ConfigureVaults.s.sol --broadcast --rpc-url $RPC_URL_BASE

# 2. Test deposit (80/20 split)
cast send $USDC "approve(address,uint256)" $CHAIN_BALANCE_MANAGER 1000000000 --private-key $TEST_USER_KEY
cast send $CHAIN_BALANCE_MANAGER "deposit(address,uint256,address)" $USDC 1000000000 $TEST_USER --private-key $TEST_USER_KEY

# 3. Verify 80% in vault
cast call $VAULT_USDC "totalAssets()(uint256)"
# Should show ~800000000 (800 USDC)

# 4. Simulate yield (owner adds yield to vault)
cast send $USDC "approve(address,uint256)" $VAULT_USDC 100000000 --private-key $DEPLOYER_KEY
cast send $VAULT_USDC "addYield(uint256)" 100000000 --private-key $DEPLOYER_KEY

# 5. Verify yield generated
cast call $VAULT_USDC "totalAssets()(uint256)"
# Should show ~900000000 (900 USDC, +100 yield)
```

---

## 📡 Phase 3: Off-Chain Indexer

The off-chain indexer reads balances from the trading chain, builds Merkle trees, and posts snapshots to Base.

### Architecture

```
┌─────────────────────────────────────────┐
│      Trading Chain (Rari/Anvil)         │
│                                         │
│  BalanceManager.balanceOf(user, token)  │
│  → Read synthetic token balances        │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│         Indexer (Node.js/TypeScript)    │
│                                         │
│  1. Query all users & balances          │
│  2. Build per-token Merkle trees        │
│  3. Post snapshot to Base               │
│  4. Store proofs in database            │
│  5. Serve API for users                 │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│       Base Chain (ChainBalanceManager)  │
│                                         │
│  updateDailySnapshot(day, snapshots)    │
│  → Store Merkle roots                   │
└─────────────────────────────────────────┘
```

### Indexer Setup (High-Level)

**Note:** The indexer will be in a separate `yield-bot` repository.

**Core Components:**

1. **Balance Reader** (`src/reader.ts`)
   ```typescript
   async function getAllBalances(token: string): Promise<UserBalance[]> {
     const holders = await getAllHolders(token);
     const balances = await Promise.all(
       holders.map(user => balanceManager.balanceOf(user, token))
     );
     return holders.map((user, i) => ({ user, balance: balances[i] }));
   }
   ```

2. **Merkle Tree Builder** (`src/merkle.ts`)
   ```typescript
   function buildTokenTree(balances: UserBalance[]): MerkleTree {
     const leaves = balances.map(({ user, balance }) =>
       ethers.solidityPackedKeccak256(['address', 'uint256'], [user, balance])
     );
     return new MerkleTree(leaves, keccak256, { sortPairs: true });
   }
   ```

3. **Snapshot Poster** (`src/poster.ts`)
   ```typescript
   async function postSnapshot(day: number, trees: TokenTree[]) {
     const snapshots = trees.map(tree => ({
       token: tree.token,
       merkleRoot: tree.root,
       totalSupply: tree.totalSupply,
       cumulativeYield: await getVaultYield(tree.token)
     }));

     await chainBalanceManager.updateDailySnapshot(day, snapshots);
   }
   ```

4. **Proof Server** (`src/api.ts`)
   ```typescript
   app.get('/proof/:user/:day/:token', async (req, res) => {
     const { user, day, token } = req.params;
     const proof = await db.getProof(user, day, token);
     res.json({ proof, balance: proof.balance, day });
   });
   ```

### Indexer Deployment

```bash
# In separate yield-bot repo
npm install
npm run build

# Configure
cp .env.example .env
# Set RPC_URL_RARI, RPC_URL_BASE, PRIVATE_KEY, etc.

# Run indexer
npm run start

# Set up daily cron job
0 0 * * * cd /path/to/yield-bot && npm run snapshot
```

---

## 🎯 Phase 4: Frontend Integration

### User Flow

1. **View Claimable Yield:**
   ```typescript
   const claimable = await chainBalanceManager.calculateClaimableYield(
     latestDay,
     USDC,
     userBalance
   );
   ```

2. **Get Merkle Proof from API:**
   ```typescript
   const response = await fetch(`https://api.gtx.com/proof/${user}/${day}/${token}`);
   const { proof, balance } = await response.json();
   ```

3. **Claim Yield:**
   ```typescript
   await chainBalanceManager.claimYield(
     day,
     token,
     balance,
     proof
   );
   ```

4. **Batch Claim Multiple Tokens:**
   ```typescript
   const proofs = [
     { token: USDC, userBalance, merkleProof: usdcProof },
     { token: WETH, userBalance, merkleProof: wethProof }
   ];
   await chainBalanceManager.claimYieldBatch(day, proofs);
   ```

---

## 📝 Phase 5: Verification & Monitoring

### Verify Deployment

```bash
# 1. Check vaults deployed
cast call $VAULT_FACTORY "getVaultCount()(uint256)"
# Should return: 4

# 2. Check ChainBalanceManager configured
cast call $CHAIN_BALANCE_MANAGER "getVault(address)(address)" $USDC
# Should return: $VAULT_USDC

# 3. Test deposit with vault integration
# (See Phase 2: Integration Test)

# 4. Check latest snapshot
cast call $CHAIN_BALANCE_MANAGER "getLatestSnapshotDay()(uint256)"

# 5. Get snapshot data
cast call $CHAIN_BALANCE_MANAGER \
  "getSnapshot(uint256,address)(bytes32,uint256,uint256)" \
  $DAY $USDC
```

### Monitor System

**Key Metrics:**
- TVL per vault
- Daily snapshots posted
- Yield generated per token
- User claims
- Gas costs

**Alerts:**
- Snapshot missed (indexer down)
- Vault liquidity low
- Unusual claim patterns

---

## 🔧 Common Operations

### Add New Token

```bash
# 1. Deploy vault
TOKEN_ADDRESS=0x...
forge script script/yield/DeployVaults.s.sol --sig "deploySimpleVault(address,string,string)" $TOKEN_ADDRESS "GTX LINK Vault" "gtxLINK" --broadcast

# 2. Configure ChainBalanceManager
cast send $CHAIN_BALANCE_MANAGER "setVault(address,address)" $TOKEN_ADDRESS $VAULT_ADDRESS --private-key $DEPLOYER_KEY

# 3. Whitelist token (if not already)
cast send $CHAIN_BALANCE_MANAGER "addToken(address)" $TOKEN_ADDRESS --private-key $DEPLOYER_KEY

# 4. Set token mapping
cast send $CHAIN_BALANCE_MANAGER "setTokenMapping(address,address)" $TOKEN_ADDRESS $SYNTHETIC_TOKEN --private-key $DEPLOYER_KEY

# Done! No code changes needed. Indexer automatically includes new token.
```

### Update Vault Ratio

```bash
# Change from 80% to 90%
cast send $CHAIN_BALANCE_MANAGER "setVaultRatio(uint256)" 9000 --private-key $DEPLOYER_KEY

# Verify
cast call $CHAIN_BALANCE_MANAGER "getVaultRatio()(uint256)"
# Returns: 9000
```

### Emergency: Remove Vault

```bash
# Set vault to address(0) - stops vault deployment
cast send $CHAIN_BALANCE_MANAGER "setVault(address,address)" $TOKEN address(0) --private-key $DEPLOYER_KEY
```

---

## 🚨 Troubleshooting

### Issue: Compilation Timeout

**Problem:** `forge build` or `forge test` times out

**Solution:**
```bash
# Clear cache
forge clean

# Build with more time
forge build --force

# Or build specific contracts
forge build src/core/ChainBalanceManager.sol
forge build src/yield/VaultFactory.sol
```

### Issue: Vault Deposit Fails

**Problem:** `deposit()` reverts when vault is configured

**Solution:**
```bash
# Check vault exists
cast call $CHAIN_BALANCE_MANAGER "getVault(address)(address)" $TOKEN

# Check vault has approval
cast call $TOKEN "allowance(address,address)(uint256)" $CHAIN_BALANCE_MANAGER $VAULT

# Check vault is ERC-4626 compliant
cast call $VAULT "asset()(address)"
cast call $VAULT "deposit(uint256,address)(uint256)" 1000 $RECIPIENT
```

### Issue: Snapshot Posting Fails

**Problem:** `updateDailySnapshot()` reverts

**Solution:**
```bash
# Check caller is owner
cast call $CHAIN_BALANCE_MANAGER "owner()(address)"

# Check array lengths match
# snapshots.length should equal number of tokens

# Check Merkle roots are valid (not 0x0)
```

### Issue: Yield Claim Fails

**Problem:** `claimYield()` reverts with "Invalid Merkle proof"

**Solution:**
1. Verify leaf construction matches contract:
   ```typescript
   // Must use solidityPackedKeccak256
   const leaf = ethers.solidityPackedKeccak256(
     ['address', 'uint256'],
     [user, balance]
   );
   ```

2. Verify proof array order
3. Verify snapshot exists for that day/token
4. Verify user balance is correct

---

## 📊 Gas Costs (Base L2)

| Operation | Gas | Cost (USD at $2 ETH, 0.5 gwei) |
|-----------|-----|--------------------------------|
| Deploy VaultFactory | ~1.5M | ~$1.50 |
| Deploy Vault (each) | ~1.2M | ~$1.20 |
| Configure Vault | ~50k | ~$0.05 |
| Deposit (with vault) | ~150k | ~$0.15 |
| Update Snapshot (10 tokens) | ~200k | ~$0.20 |
| Claim Single Token | ~100k | ~$0.10 |
| Claim Batch (3 tokens) | ~250k | ~$0.25 |

**Total Setup Cost:** ~$10-15 (one-time)
**Monthly Operating Cost:** ~$6-10 (daily snapshots)

---

## ✅ Deployment Checklist

### Smart Contracts
- [ ] Deploy VaultFactory
- [ ] Deploy vaults for all tokens
- [ ] Configure ChainBalanceManager with vaults
- [ ] Set vault ratio (80%)
- [ ] Test deposit with vault integration
- [ ] Verify vaults receive 80% of deposits

### Off-Chain
- [ ] Set up yield-bot indexer
- [ ] Configure RPC URLs and keys
- [ ] Test balance reading from Rari
- [ ] Test Merkle tree building
- [ ] Test snapshot posting to Base
- [ ] Set up database for proofs
- [ ] Deploy API server
- [ ] Set up daily cron job
- [ ] Monitor indexer health

### Frontend
- [ ] Integrate claimable yield display
- [ ] Add proof fetching from API
- [ ] Add claim button with Merkle proof
- [ ] Add batch claim for multiple tokens
- [ ] Show yield history
- [ ] Display APY per token

### Testing
- [ ] Run all unit tests
- [ ] Run integration tests
- [ ] Test full user flow
- [ ] Test edge cases (zero balance, invalid proof, etc.)
- [ ] Load test (many users)
- [ ] Security review

### Monitoring
- [ ] Set up metrics dashboard
- [ ] Alert on missed snapshots
- [ ] Alert on low vault liquidity
- [ ] Monitor gas costs
- [ ] Track TVL and yield

---

## 📚 Additional Resources

- **Architecture Docs:** `docs/YIELD_SYSTEM_README.md`
- **Testing Guide:** `docs/YIELD_TESTING_GUIDE.md`
- **Implementation Details:** `docs/YIELD_IMPLEMENTATION_SUMMARY.md`
- **Plans:** `plans/01-06-*.md`
- **Smart Contracts:**
  - ChainBalanceManager: `src/core/ChainBalanceManager.sol`
  - VaultFactory: `src/yield/VaultFactory.sol`
  - Storage: `src/core/storages/ChainBalanceManagerStorage.sol`
- **Tests:**
  - Yield Tests: `test/core/ChainBalanceManagerYieldTest.t.sol`
  - Mock Vault: `src/mocks/MockERC4626Vault.sol`

---

**Status:** Ready for deployment after compilation completes ✅

**Next:** Deploy to testnet → Test → Deploy indexer → Launch! 🚀
