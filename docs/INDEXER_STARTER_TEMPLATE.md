### GTX Yield Indexer - Starter Template

This is a high-level template for the off-chain indexer (`yield-bot` repository).

## Directory Structure

```
yield-bot/
├─ src/
│  ├─ reader.ts          # Read balances from trading chain
│  ├─ merkle.ts          # Build Merkle trees
│  ├─ poster.ts          # Post snapshots to Base
│  ├─ api.ts             # API server for proofs
│  ├─ db.ts              # Database operations
│  └─ config.ts          # Configuration
├─ scripts/
│  └─ snapshot.ts        # Daily snapshot job
├─ test/
│  └─ *.test.ts          # Tests
├─ package.json
├─ tsconfig.json
└─ .env.example
```

## Core Files

### 1. `src/config.ts`

```typescript
import { ethers } from "ethers";

export const config = {
  // RPCs
  rariRpcUrl: process.env.RPC_URL_RARI!,
  baseRpcUrl: process.env.RPC_URL_BASE!,

  // Contracts
  balanceManagerAddress: process.env.BALANCE_MANAGER_ADDRESS!,
  chainBalanceManagerAddress: process.env.CHAIN_BALANCE_MANAGER_ADDRESS!,

  // Tokens
  tokens: {
    USDC: process.env.USDC_ADDRESS!,
    WETH: process.env.WETH_ADDRESS!,
    WBTC: process.env.WBTC_ADDRESS!,
    USDT: process.env.USDT_ADDRESS!,
  },

  // Vaults
  vaults: {
    USDC: process.env.VAULT_USDC_ADDRESS!,
    WETH: process.env.VAULT_WETH_ADDRESS!,
    WBTC: process.env.VAULT_WBTC_ADDRESS!,
    USDT: process.env.VAULT_USDT_ADDRESS!,
  },

  // Database
  databaseUrl: process.env.DATABASE_URL!,

  // Private key for posting snapshots
  deployerPrivateKey: process.env.DEPLOYER_PRIVATE_KEY!,
};

// Providers
export const rariProvider = new ethers.JsonRpcProvider(config.rariRpcUrl);
export const baseProvider = new ethers.JsonRpcProvider(config.baseRpcUrl);
export const deployer = new ethers.Wallet(config.deployerPrivateKey, baseProvider);
```

### 2. `src/reader.ts`

```typescript
import { ethers } from "ethers";
import { config, rariProvider } from "./config";

// BalanceManager ABI (minimal)
const balanceManagerAbi = [
  "function balanceOf(address user, address token) view returns (uint256)",
  "function getBalance(address user, uint256 currencyId) view returns (uint256)",
];

export interface UserBalance {
  user: string;
  balance: bigint;
}

/**
 * Read all balances for a token from BalanceManager on trading chain
 */
export async function getAllBalances(token: string): Promise<UserBalance[]> {
  const balanceManager = new ethers.Contract(
    config.balanceManagerAddress,
    balanceManagerAbi,
    rariProvider
  );

  // Get all users (implementation depends on your indexing strategy)
  // Option 1: Listen to deposit events
  // Option 2: Use The Graph subgraph
  // Option 3: Query from database
  const users = await getAllUsers(); // Implement this

  const balances: UserBalance[] = [];

  for (const user of users) {
    try {
      const balance = await balanceManager.balanceOf(user, token);
      if (balance > 0n) {
        balances.push({ user, balance });
      }
    } catch (error) {
      console.error(`Failed to get balance for ${user}:`, error);
    }
  }

  return balances;
}

/**
 * Get all users who have ever interacted with the system
 * This should be implemented using event indexing or a subgraph
 */
async function getAllUsers(): Promise<string[]> {
  // TODO: Implement using:
  // 1. The Graph subgraph
  // 2. Event logs (Deposit, Withdraw events)
  // 3. Database cache
  // 4. Combination of above

  // For now, return from env or database
  return []; // Replace with actual implementation
}
```

### 3. `src/merkle.ts`

```typescript
import { ethers } from "ethers";
import { MerkleTree } from "merkletreejs";
import keccak256 from "keccak256";
import { UserBalance } from "./reader";

export interface TokenMerkleTree {
  token: string;
  root: string;
  tree: MerkleTree;
  totalSupply: bigint;
  leaves: { user: string; balance: bigint; leaf: string }[];
}

/**
 * Build Merkle tree for a token
 * Leaf structure: keccak256(abi.encodePacked(user, balance))
 */
export function buildTokenTree(
  token: string,
  balances: UserBalance[]
): TokenMerkleTree {
  // Build leaves (same as Solidity: keccak256(abi.encodePacked(user, balance)))
  const leaves = balances.map(({ user, balance }) => {
    const leaf = ethers.solidityPackedKeccak256(
      ["address", "uint256"],
      [user, balance]
    );
    return { user, balance, leaf };
  });

  // Sort leaves for deterministic tree
  const sortedLeaves = leaves.sort((a, b) => a.leaf.localeCompare(b.leaf));

  // Build Merkle tree
  const tree = new MerkleTree(
    sortedLeaves.map((l) => l.leaf),
    keccak256,
    { sortPairs: true }
  );

  const root = tree.getHexRoot();

  // Calculate total supply
  const totalSupply = balances.reduce((sum, b) => sum + b.balance, 0n);

  return {
    token,
    root,
    tree,
    totalSupply,
    leaves: sortedLeaves,
  };
}

/**
 * Get Merkle proof for a user
 */
export function getProof(tree: TokenMerkleTree, user: string): string[] {
  const leafData = tree.leaves.find(
    (l) => l.user.toLowerCase() === user.toLowerCase()
  );

  if (!leafData) {
    throw new Error(`User ${user} not found in tree`);
  }

  return tree.tree.getHexProof(leafData.leaf);
}
```

### 4. `src/poster.ts`

```typescript
import { ethers } from "ethers";
import { config, deployer } from "./config";
import { TokenMerkleTree } from "./merkle";

// ChainBalanceManager ABI (minimal)
const chainBalanceManagerAbi = [
  "function updateDailySnapshot(uint256 day, tuple(address token, bytes32 merkleRoot, uint256 totalSupply, uint256 cumulativeYield)[] snapshots)",
  "function getVault(address token) view returns (address)",
];

// ERC-4626 ABI (minimal)
const erc4626Abi = [
  "function totalAssets() view returns (uint256)",
  "function asset() view returns (address)",
];

/**
 * Get cumulative yield from vault
 */
async function getVaultYield(token: string): Promise<bigint> {
  const cbm = new ethers.Contract(
    config.chainBalanceManagerAddress,
    chainBalanceManagerAbi,
    deployer
  );

  const vaultAddress = await cbm.getVault(token);
  if (vaultAddress === ethers.ZeroAddress) {
    return 0n;
  }

  const vault = new ethers.Contract(vaultAddress, erc4626Abi, deployer);
  const totalAssets = await vault.totalAssets();

  // TODO: Track cumulative yield over time
  // For now, return total assets (simplified)
  return totalAssets;
}

/**
 * Post daily snapshot to ChainBalanceManager
 */
export async function postSnapshot(
  day: number,
  trees: TokenMerkleTree[]
): Promise<void> {
  console.log(`\n=== Posting Snapshot for Day ${day} ===`);

  const cbm = new ethers.Contract(
    config.chainBalanceManagerAddress,
    chainBalanceManagerAbi,
    deployer
  );

  // Build snapshots array
  const snapshots = await Promise.all(
    trees.map(async (tree) => ({
      token: tree.token,
      merkleRoot: tree.root,
      totalSupply: tree.totalSupply,
      cumulativeYield: await getVaultYield(tree.token),
    }))
  );

  console.log("Snapshots:", snapshots);

  // Post to chain
  const tx = await cbm.updateDailySnapshot(day, snapshots);
  console.log("Transaction sent:", tx.hash);

  const receipt = await tx.wait();
  console.log("Transaction confirmed in block:", receipt.blockNumber);

  console.log("✅ Snapshot posted successfully!");
}
```

### 5. `src/db.ts`

```typescript
import { Pool } from "pg";
import { config } from "./config";
import { TokenMerkleTree } from "./merkle";

const pool = new Pool({
  connectionString: config.databaseUrl,
});

/**
 * Store snapshot and proofs in database
 */
export async function storeSnapshot(
  day: number,
  trees: TokenMerkleTree[]
): Promise<void> {
  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    // Store snapshot
    for (const tree of trees) {
      await client.query(
        `INSERT INTO snapshots (day, token, merkle_root, total_supply, timestamp)
         VALUES ($1, $2, $3, $4, NOW())
         ON CONFLICT (day, token) DO UPDATE SET
           merkle_root = $3,
           total_supply = $4,
           timestamp = NOW()`,
        [day, tree.token, tree.root, tree.totalSupply.toString()]
      );

      // Store proofs for each user
      for (const leaf of tree.leaves) {
        const proof = tree.tree.getHexProof(leaf.leaf);

        await client.query(
          `INSERT INTO proofs (day, token, user_address, balance, proof, leaf)
           VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (day, token, user_address) DO UPDATE SET
             balance = $4,
             proof = $5,
             leaf = $6`,
          [
            day,
            tree.token,
            leaf.user,
            leaf.balance.toString(),
            JSON.stringify(proof),
            leaf.leaf,
          ]
        );
      }
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Get proof for a user
 */
export async function getProof(
  user: string,
  day: number,
  token: string
): Promise<{
  proof: string[];
  balance: string;
  leaf: string;
} | null> {
  const result = await pool.query(
    `SELECT proof, balance, leaf FROM proofs
     WHERE user_address = $1 AND day = $2 AND token = $3`,
    [user.toLowerCase(), day, token.toLowerCase()]
  );

  if (result.rows.length === 0) {
    return null;
  }

  const row = result.rows[0];
  return {
    proof: JSON.parse(row.proof),
    balance: row.balance,
    leaf: row.leaf,
  };
}
```

### 6. `src/api.ts`

```typescript
import express from "express";
import { getProof } from "./db";
import { config } from "./config";

const app = express();
const PORT = process.env.PORT || 3000;

/**
 * Get proof for a user for a specific day and token
 */
app.get("/proof/:user/:day/:token", async (req, res) => {
  try {
    const { user, day, token } = req.params;
    const proof = await getProof(user, parseInt(day), token);

    if (!proof) {
      return res.status(404).json({
        error: "Proof not found",
        user,
        day,
        token,
      });
    }

    res.json({
      user,
      day: parseInt(day),
      token,
      balance: proof.balance,
      proof: proof.proof,
      leaf: proof.leaf,
    });
  } catch (error) {
    console.error("Error getting proof:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * Get all proofs for a user for a specific day
 */
app.get("/proofs/:user/:day", async (req, res) => {
  try {
    const { user, day } = req.params;
    const tokens = Object.values(config.tokens);

    const proofs = await Promise.all(
      tokens.map(async (token) => {
        const proof = await getProof(user, parseInt(day), token);
        return proof ? { token, ...proof } : null;
      })
    );

    res.json({
      user,
      day: parseInt(day),
      proofs: proofs.filter((p) => p !== null),
    });
  } catch (error) {
    console.error("Error getting proofs:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * Health check
 */
app.get("/health", (req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`API server listening on port ${PORT}`);
});
```

### 7. `scripts/snapshot.ts`

```typescript
import { getAllBalances } from "../src/reader";
import { buildTokenTree } from "../src/merkle";
import { postSnapshot } from "../src/poster";
import { storeSnapshot } from "../src/db";
import { config } from "../src/config";

/**
 * Daily snapshot job
 * Run via: npm run snapshot
 * Or cron: 0 0 * * * cd /path/to/yield-bot && npm run snapshot
 */
async function main() {
  console.log("=== Starting Daily Snapshot ===");
  console.log("Time:", new Date().toISOString());

  // Calculate day (e.g., days since epoch)
  const day = Math.floor(Date.now() / 86400000);
  console.log("Day:", day);

  // Build trees for all tokens
  const trees = [];

  for (const [symbol, address] of Object.entries(config.tokens)) {
    console.log(`\nProcessing ${symbol}...`);

    // Read balances
    const balances = await getAllBalances(address);
    console.log(`Found ${balances.length} holders`);

    // Build Merkle tree
    const tree = buildTokenTree(address, balances);
    console.log(`Root: ${tree.root}`);
    console.log(`Total supply: ${tree.totalSupply}`);

    trees.push(tree);
  }

  // Store in database
  console.log("\nStoring in database...");
  await storeSnapshot(day, trees);

  // Post to chain
  console.log("\nPosting to chain...");
  await postSnapshot(day, trees);

  console.log("\n✅ Snapshot complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error:", error);
    process.exit(1);
  });
```

### 8. `package.json`

```json
{
  "name": "gtx-yield-bot",
  "version": "1.0.0",
  "scripts": {
    "start": "ts-node src/api.ts",
    "snapshot": "ts-node scripts/snapshot.ts",
    "test": "jest"
  },
  "dependencies": {
    "ethers": "^6.8.0",
    "express": "^4.18.2",
    "merkletreejs": "^0.3.11",
    "keccak256": "^1.0.6",
    "pg": "^8.11.0",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "@types/express": "^4.17.20",
    "@types/node": "^20.8.0",
    "ts-node": "^10.9.1",
    "typescript": "^5.2.2",
    "jest": "^29.7.0"
  }
}
```

### 9. `.env.example`

```bash
# RPC URLs
RPC_URL_RARI=https://rari-testnet.rpc.caldera.xyz/http
RPC_URL_BASE=https://sepolia.base.org

# Contract Addresses
BALANCE_MANAGER_ADDRESS=0x...
CHAIN_BALANCE_MANAGER_ADDRESS=0x...

# Token Addresses
USDC_ADDRESS=0x...
WETH_ADDRESS=0x...
WBTC_ADDRESS=0x...
USDT_ADDRESS=0x...

# Vault Addresses
VAULT_USDC_ADDRESS=0x...
VAULT_WETH_ADDRESS=0x...
VAULT_WBTC_ADDRESS=0x...
VAULT_USDT_ADDRESS=0x...

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/gtx_yield

# Deployer (for posting snapshots)
DEPLOYER_PRIVATE_KEY=0x...

# API
PORT=3000
```

### 10. Database Schema

```sql
-- snapshots table
CREATE TABLE snapshots (
  day INTEGER NOT NULL,
  token VARCHAR(42) NOT NULL,
  merkle_root VARCHAR(66) NOT NULL,
  total_supply VARCHAR(78) NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  PRIMARY KEY (day, token)
);

-- proofs table
CREATE TABLE proofs (
  day INTEGER NOT NULL,
  token VARCHAR(42) NOT NULL,
  user_address VARCHAR(42) NOT NULL,
  balance VARCHAR(78) NOT NULL,
  proof JSONB NOT NULL,
  leaf VARCHAR(66) NOT NULL,
  PRIMARY KEY (day, token, user_address),
  FOREIGN KEY (day, token) REFERENCES snapshots(day, token)
);

-- indexes
CREATE INDEX idx_proofs_user ON proofs(user_address);
CREATE INDEX idx_proofs_day ON proofs(day);
CREATE INDEX idx_snapshots_day ON snapshots(day);
```

## Usage

### Setup

```bash
# Install dependencies
npm install

# Setup database
psql -d gtx_yield < schema.sql

# Configure
cp .env.example .env
# Edit .env with your values
```

### Run

```bash
# Start API server
npm run start

# Run daily snapshot
npm run snapshot

# Set up cron job
crontab -e
# Add: 0 0 * * * cd /path/to/yield-bot && npm run snapshot
```

### Test

```bash
# Test API
curl http://localhost:3000/health

# Test proof retrieval
curl http://localhost:3000/proof/0x.../1/0x...
```

---

**Note:** This is a starter template. For production:
1. Add error handling and retries
2. Implement proper event indexing (The Graph subgraph)
3. Add monitoring and alerting
4. Use multi-indexer consensus
5. Add rate limiting to API
6. Implement caching
7. Add authentication if needed
8. Use TypeORM or Prisma for database
9. Add comprehensive tests
10. Deploy with Docker/Kubernetes

---

**Status:** Template ready for implementation ✅

**Next:** Implement in separate `yield-bot` repository
