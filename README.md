# 🚀 CLOB DEX - Cross-Chain Decentralized Exchange

> 🌉 Multi-chain CLOB with unified liquidity across Espresso testnet

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hyperlane](https://img.shields.io/badge/CrossChain-Hyperlane-green)](https://hyperlane.xyz)
[![Status](https://img.shields.io/badge/Status-OPERATIONAL-brightgreen)](docs/CROSS_CHAIN_STATUS.md)
[![Espresso](https://img.shields.io/badge/Network-Espresso-purple)](https://docs.espresso.network)

## 🌟 Vision

A unified cross-chain trading hub powered by Central Limit Order Book (CLOB) technology. Bridge assets from multiple chains and trade with unified liquidity on Rari testnet, bringing together the best of CEX performance and DEX trustlessness.

## 🎯 **System Status: OPERATIONAL** ✅

The cross-chain CLOB DEX is **fully deployed and working**! 

- 🌉 **Cross-chain messaging**: ENABLED via Hyperlane
- 🔄 **Token bridging**: OPERATIONAL (USDT → gsUSDT)  
- 📊 **CLOB trading**: READY on Rari testnet
- 🔍 **Message tracking**: [Hyperlane Explorer](https://hyperlane-explorer.gtxdex.xyz/)

📋 [View detailed status report](docs/CROSS_CHAIN_STATUS.md)

## 🏗️ Cross-Chain Architecture

```
┌─────────────────────┐    Hyperlane Bridge    ┌──────────────────────────┐
│   SOURCE CHAINS     │ ─────────────────────► │     RARI TRADING HUB     │
│                     │                        │                          │
│ • Appchain (4661)   │   Message Dispatch     │ • BalanceManager         │
│ • Arbitrum Sepolia  │ ◄───────────────────── │ • PoolManager            │
│ • Rise Sepolia      │   Withdrawal Flow      │ • OrderBook (RB-Tree)    │
│                     │                        │ • Router                 │
│ ChainBalanceManager │                        │                          │
│ • Lock USDT/WETH    │                        │ Synthetic Tokens:        │
│ • Bridge to gsTokens│                        │ • gsUSDT, gsWETH, gsWBTC │
│ • Handle withdraws  │                        │                          │
└─────────────────────┘                        └──────────────────────────┘
```

### **Core Components**
- **ChainBalanceManager**: Source chain vault contracts for token locking
- **BalanceManager**: Rari trading account manager with cross-chain message handling
- **PoolManager**: Trading pair management and pool deployments  
- **OrderBook**: CLOB with Red-Black Tree for efficient order matching
- **Router**: User-friendly trading interface and swap execution

## 💎 Core Features

### 🗃️ Optimized Order Management

- **Packed Order Structure**
  ```solidity
  struct Order {
      address user;         // User who placed the order
      uint48 id;            // Unique identifier
      uint48 next;          // Next order in queue
      uint128 quantity;     // Total order quantity
      uint128 filled;       // Filled amount
      uint128 price;        // Order price
      uint48 prev;          // Previous order in queue
      uint48 expiry;        // Expiration timestamp
      Status status;        // Current status
      OrderType orderType;  // LIMIT or MARKET
      Side side;            // BUY or SELL
  }
  ```

- **Order Queue Management**: Double-linked list implementation for FIFO order execution
  ```solidity
  struct OrderQueue {
      uint256 totalVolume;  // Total volume at price level
      uint48 orderCount;    // Number of orders
      uint48 head;          // First order in queue
      uint48 tail;          // Last order in queue
  }
  ```

### 🔑 Efficient Data Structures

- **Price Level Indexing**: Red-Black Tree for O(log n) price lookup
  ```solidity
  mapping(Side => RedBlackTreeLib.Tree) private priceTrees;
  ```

- **Order Storage**: Optimized for gas efficiency and quick access
  ```solidity
  mapping(uint48 => Order) private orders;
  mapping(Side => mapping(uint128 => OrderQueue)) private orderQueues;
  ```

### 💰 Sophisticated Balance Management

- **Balance Tracking**: Per-user balance tracking for multiple currencies
  ```solidity
  mapping(address => mapping(uint256 => uint256)) private balanceOf;
  ```

- **Order Lock System**: Balance locking prevents double-spending
  ```solidity
  mapping(address => mapping(address => mapping(uint256 => uint256))) private lockedBalanceOf;
  ```

- **Operator Authorization**: Controlled access to manage user funds
  ```solidity
  mapping(address => bool) private authorizedOperators;
  ```

## ⛽ Gas Optimization Techniques

1. **Optimized Storage Access**
    - Packed struct layouts reduce storage operations
    - Minimized SSTOREs through strategic updates
    - Efficient order data retrieval patterns

2. **Advanced Data Structures**
    - Red-Black Tree for price levels (O(log n) operations)
    - Double-linked list for order queue management
    - Automatic price level cleanup for unused levels

3. **Balance Management**
    - Lock-and-execute pattern prevents unnecessary transfers
    - Direct balance transfers between users within the contract

## 🔒 Security Features

1. **Balance Protection**
    - Order amount locking before placement
    - Atomicity in balance operations
    - Authorization checks for operators

2. **Order Integrity**
    - Order ownership validation
    - Expiration handling
    - Time-in-force constraints enforcement

3. **Access Control**
    - Router authorization for order operations
    - Owner-only configuration changes
    - Operator-limited permissions

## 📊 Market Order Execution

1. **Efficient Matching**
    - Best price traversal using Red-Black Tree
    - Volume-based execution across price levels
    - Auto-cancellation of unfilled IOC/FOK orders

2. **Multi-Currency Support**
    - Automatic currency conversion for trades
    - Multi-hop swap routing
    - Intermediary currency support

## 🔄 Order Lifecycle Management

1. **Order Placement**
    - Validation of parameters (price, quantity, trading rules)
    - Balance locking
    - Insertion into appropriate price level queue

2. **Order Matching**
    - FIFO execution against opposite side orders
    - Partial fills tracking
    - Balance transfers between counterparties

3. **Order Cancellation/Expiration**
    - Removal from order queue
    - Balance unlocking
    - Automatic price level cleanup

The implementation ensures efficient order management while maintaining robust security measures and optimizing for gas usage across all operations.

## 📜 Contract Addresses

The contract addresses are stored in JSON files under the `deployments/<chain_id>.json`. Example folder:

- 🔗 **Local Development**: `deployments/31337.json` (Anvil network)
- 🌐 **GTX Dev Network**: `deployments/31338.json` (GTX Development)
- 🚀 **Rise Network**: `deployments/11155931.json` (Rise Sepolia)
- 🌟 **Pharos Network**: `deployments/50002.json` (Pharos Devnet)

To access contract addresses for a specific network:
1. Locate the appropriate JSON file for your target network
2. Parse the JSON to find the contract you need (e.g., `GTXRouter`, `PoolManager`)
3. Use the address in your frontend or for contract interactions

## 📜 Contract ABIs

The contract ABIs are stored in the `deployed-contracts/deployedContracts.ts` file.

**Note**: This file is automatically generated using the `generate-abi` target in the `Makefile`. Ensure you run the appropriate Makefile command to update or regenerate the ABIs when needed.

## Foundry Smart Contract Setup Guide

This document provides a comprehensive guide for setting up, deploying, and upgrading smart contracts using Foundry. Follow the instructions below to get started.

---

## Prerequisites

Before proceeding, ensure you have the following installed:

- [Foundry](https://book.getfoundry.sh/)
- Node.js (required for generating ABI files)
- A compatible Ethereum wallet for broadcasting transactions
- A `.env` file to configure network and wallet details

---

## Installation and Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/Great-Trading-eXperience/clob-dex.git
   cd clob-dex
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Duplicate the `.env.example` file in the root directory, rename it to `.env`, and set the required variables.

## 🚀 Quick Start - Cross-Chain Trading

### **Step 1: Bridge Assets to Rari**
```solidity
// On Appchain: Deposit USDT for cross-chain bridging
chainBalanceManager.deposit(
    0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516, // USDT address
    amount,
    recipient
);
```

### **Step 2: Trade on Rari**
```solidity  
// On Rari: Trade synthetic tokens
router.swapExactIn(
    gsUSDT,    // 0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7
    gsWETH,    // 0xC7A1777e80982E01e07406e6C6E8B30F5968F836  
    amount,
    minOut
);
```

### **Step 3: Monitor Bridge Status**
- **Hyperlane Explorer**: https://hyperlane-explorer.gtxdex.xyz/
- **Test Transaction**: [View Message](https://hyperlane-explorer.gtxdex.xyz/message/0xfcadbcd23563cb0230070d9ead7f78a0c0e468c7a7d3c674858afc60ca0a013a)

### **Contract Addresses**

| Network | Contract | Address |
|---------|----------|---------|
| **Appchain** | ChainBalanceManager | `0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7` |
| **Appchain** | USDT | `0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516` |
| **Rari** | BalanceManager | `0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5` |
| **Rari** | gsUSDT | `0x3d17BF5d39A96d5B4D76b40A7f74c0d02d2fadF7` |
| **Rari** | Router | `0xF38489749c3e65c82a9273c498A8c6614c34754b` |

---

## Deployment Guide

For complete deployment instructions, see **[📋 DEPLOYMENT.md](docs/DEPLOYMENT.md)**

### Quick Deployment
```bash
# Deploy and validate the complete two-chain system
make validate-deployment           # Validate core deployment
make validate-cross-chain-deposit  # Validate cross-chain system
```

### Single Network Deployment
To deploy contracts to a single network:
```bash
make deploy network=<network_name>
```
- Example:
  ```bash
  make deploy network=riseSepolia
  ```

### Deploying and Verifying Contracts
To deploy and verify contracts:
```bash
make deploy-verify network=<network_name>
```

---

## Data Population

For populating the system with demo trading data, see **[📊 DATA_POPULATION.md](docs/DATA_POPULATION.md)**

### Quick Data Population
```bash
# Populate system with traders, liquidity, and trading activity
make validate-data-population
```

---

## Mock Contracts Deployment

### Deploying Mocks
To deploy mock contracts, use:
```bash
make deploy-mocks network=<network_name>
```

### Deploying and Verifying Mocks
To deploy and verify mock contracts:
```bash
make deploy-mocks-verify network=<network_name>
```

### Fill Mock Order Book
To populate the ETH/USDC order book with sample orders:
```bash
make fill-orderbook network=<network_name>
```

## Contract Upgrades

### Upgrading Contracts
To upgrade contracts:
```bash
make upgrade network=<network_name>
```

### Upgrading and Verifying Contracts
To upgrade and verify contracts:
```bash
make upgrade-verify network=<network_name>
```

---

## Additional Commands

- **Compile Contracts**
  ```bash
  make compile
  ```

- **Run Tests**
  ```bash
  make test
  ```

- **Lint Code**
  ```bash
  make lint
  ```

- **Generate ABI Files**
  ```bash
  make generate-abi
  ```

- **Help**
  Display all Makefile targets:
  ```bash
  make help
  ```

---

## Notes

- Replace `<network_name>` with the desired network (e.g., `arbitrumSepolia`, `mainnet`).
- Ensure your `.env` file is correctly configured to avoid deployment errors.
- Use the `help` target to quickly review all available commands:
  ```bash
  make help
  ```
