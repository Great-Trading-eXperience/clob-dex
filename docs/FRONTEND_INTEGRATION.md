# Frontend Integration Guide

This guide shows how to integrate the Cross-Chain CLOB DEX into your frontend application using viem.

## Overview

The Cross-Chain CLOB DEX allows users to:
- **Deposit** tokens from source chains (Appchain, Rise Sepolia, Arbitrum Sepolia) 
- **Trade** with synthetic tokens on Rari testnet
- **Withdraw** back to any supported source chain

## Quick Start

### Installation

```bash
npm install viem
```

### Basic Setup

```typescript
import { CrossChainCLOBClient } from './cross-chain-client'

// Initialize client with user's private key
const client = new CrossChainCLOBClient(userPrivateKey)
```

## Core Functions

### 1. Cross-Chain Deposit

Deposit tokens from any source chain to get synthetic tokens on Rari for trading.

```typescript
// Deposit 100 USDT from Arbitrum Sepolia to Rari
const txHash = await client.deposit(
  'arbitrumSepolia',  // Source chain
  'USDT',             // Token
  '100',              // Amount  
  userAddress         // Recipient (optional)
)

console.log(`Deposit transaction: ${txHash}`)
// Wait 1-2 minutes for Hyperlane relayers to process cross-chain message
```

### 2. Check Balances

```typescript
// Check synthetic token balance on Rari (for trading)
const gsUSDTBalance = await client.getSyntheticBalance('USDT')
console.log(`Available for trading: ${gsUSDTBalance} gsUSDT`)

// Check source chain balance
const sourceBalance = await client.getSourceBalance('arbitrumSepolia', 'USDT')
console.log(`Source balance: ${sourceBalance} USDT`)
```

### 3. Cross-Chain Withdrawal

Withdraw synthetic tokens back to any source chain.

```typescript
// Withdraw 50 gsUSDT from Rari to Appchain as USDT
const txHash = await client.withdraw(
  'USDT',      // Token type
  '50',        // Amount of synthetic token
  'appchain',  // Destination chain
  userAddress  // Recipient
)

console.log(`Withdrawal transaction: ${txHash}`)
```

## React Integration

### Custom Hook

```typescript
import { useCrossChainCLOB } from './cross-chain-client'
import { useState, useEffect } from 'react'

function TradingDashboard() {
  const client = useCrossChainCLOB(userPrivateKey)
  const [portfolio, setPortfolio] = useState(null)
  const [loading, setLoading] = useState(false)

  // Load user portfolio
  useEffect(() => {
    async function loadPortfolio() {
      const data = await client.getPortfolio()
      setPortfolio(data)
    }
    loadPortfolio()
  }, [])

  // Deposit handler
  const handleDeposit = async (chain, token, amount) => {
    setLoading(true)
    try {
      const tx = await client.deposit(chain, token, amount)
      console.log('Deposit successful:', tx)
      // Refresh portfolio after confirmation
      setTimeout(() => loadPortfolio(), 60000) // Wait 1 min for cross-chain
    } catch (error) {
      console.error('Deposit failed:', error)
    }
    setLoading(false)
  }

  return (
    <div>
      <h2>Cross-Chain Trading Dashboard</h2>
      
      {/* Portfolio Display */}
      {portfolio && (
        <div>
          <h3>Your Balances</h3>
          
          {/* Source Chain Balances */}
          <div>
            <h4>Source Chains</h4>
            {Object.entries(portfolio.sourceChains).map(([chain, tokens]) => (
              <div key={chain}>
                <strong>{chain}:</strong>
                {Object.entries(tokens).map(([token, balance]) => (
                  <span key={token}> {balance} {token} </span>
                ))}
              </div>
            ))}
          </div>
          
          {/* Rari Trading Balances */}
          <div>
            <h4>Available for Trading (Rari)</h4>
            {Object.entries(portfolio.rari).map(([token, balance]) => (
              <div key={token}>{balance} {token}</div>
            ))}
          </div>
        </div>
      )}
      
      {/* Deposit Form */}
      <div>
        <h3>Deposit to Trade</h3>
        <button 
          onClick={() => handleDeposit('arbitrumSepolia', 'USDT', '100')}
          disabled={loading}
        >
          Deposit 100 USDT from Arbitrum
        </button>
      </div>
    </div>
  )
}
```

### Complete Trading Interface

```typescript
import { useState } from 'react'

function CrossChainTradingInterface() {
  const client = useCrossChainCLOB(userPrivateKey)
  const [selectedChain, setSelectedChain] = useState('arbitrumSepolia')
  const [selectedToken, setSelectedToken] = useState('USDT')
  const [amount, setAmount] = useState('')
  const [operation, setOperation] = useState('deposit') // 'deposit' | 'withdraw'

  const chains = [
    { id: 'arbitrumSepolia', name: 'Arbitrum Sepolia' },
    { id: 'appchain', name: 'Appchain Testnet' },
    { id: 'riseSepolia', name: 'Rise Sepolia' }
  ]

  const tokens = ['USDT', 'WETH', 'WBTC']

  const handleTransaction = async () => {
    try {
      if (operation === 'deposit') {
        const tx = await client.deposit(selectedChain, selectedToken, amount)
        alert(`Deposit initiated: ${tx}`)
      } else {
        const tx = await client.withdraw(selectedToken, amount, selectedChain)
        alert(`Withdrawal initiated: ${tx}`)
      }
    } catch (error) {
      alert(`Transaction failed: ${error.message}`)
    }
  }

  return (
    <div className="trading-interface">
      <h2>Cross-Chain CLOB Trading</h2>
      
      {/* Operation Toggle */}
      <div>
        <label>
          <input 
            type="radio" 
            value="deposit" 
            checked={operation === 'deposit'}
            onChange={(e) => setOperation(e.target.value)}
          />
          Deposit (to trade)
        </label>
        <label>
          <input 
            type="radio" 
            value="withdraw" 
            checked={operation === 'withdraw'}
            onChange={(e) => setOperation(e.target.value)}
          />
          Withdraw (from trading)
        </label>
      </div>

      {/* Chain Selection */}
      <div>
        <label>Chain:</label>
        <select 
          value={selectedChain} 
          onChange={(e) => setSelectedChain(e.target.value)}
        >
          {chains.map(chain => (
            <option key={chain.id} value={chain.id}>
              {chain.name}
            </option>
          ))}
        </select>
      </div>

      {/* Token Selection */}
      <div>
        <label>Token:</label>
        <select 
          value={selectedToken} 
          onChange={(e) => setSelectedToken(e.target.value)}
        >
          {tokens.map(token => (
            <option key={token} value={token}>{token}</option>
          ))}
        </select>
      </div>

      {/* Amount Input */}
      <div>
        <label>Amount:</label>
        <input 
          type="number" 
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0.0"
        />
      </div>

      {/* Submit Button */}
      <button onClick={handleTransaction}>
        {operation === 'deposit' ? 'Deposit to Trade' : 'Withdraw to Chain'}
      </button>

      {/* Helper Text */}
      <div className="helper-text">
        {operation === 'deposit' ? (
          <p>💡 Deposit tokens to get synthetic tokens (gs{selectedToken}) for trading on Rari</p>
        ) : (
          <p>💡 Withdraw your synthetic tokens back to {selectedChain}</p>
        )}
      </div>
    </div>
  )
}
```

## Advanced Features

### Real-time Balance Updates

```typescript
import { useEffect, useState } from 'react'

function useRealtimeBalances(client, userAddress) {
  const [balances, setBalances] = useState({})
  const [loading, setLoading] = useState(true)

  // Poll balances every 30 seconds
  useEffect(() => {
    const updateBalances = async () => {
      try {
        const portfolio = await client.getPortfolio(userAddress)
        setBalances(portfolio)
      } catch (error) {
        console.error('Failed to update balances:', error)
      }
      setLoading(false)
    }

    updateBalances()
    const interval = setInterval(updateBalances, 30000)
    
    return () => clearInterval(interval)
  }, [client, userAddress])

  return { balances, loading }
}
```

### Transaction Status Tracking

```typescript
function useTransactionStatus(txHash, sourceChain) {
  const [status, setStatus] = useState('pending')
  const client = useCrossChainCLOB(userPrivateKey)

  useEffect(() => {
    if (!txHash) return

    const trackTransaction = async () => {
      try {
        // Wait for source chain confirmation
        const receipt = await client.sourceClients.get(sourceChain)
          .waitForTransactionReceipt({ hash: txHash })
        
        setStatus('confirmed')
        
        // For cross-chain ops, wait for destination confirmation
        setTimeout(() => {
          setStatus('cross_chain_complete')
        }, 60000) // Estimate 1 minute for Hyperlane

      } catch (error) {
        setStatus('failed')
      }
    }

    trackTransaction()
  }, [txHash, sourceChain])

  return status
}
```

### Error Handling Best Practices

```typescript
async function safeDeposit(client, chain, token, amount) {
  try {
    // 1. Validate inputs
    if (!amount || parseFloat(amount) <= 0) {
      throw new Error('Amount must be greater than 0')
    }

    // 2. Check balance before transaction
    const balance = await client.getSourceBalance(chain, token)
    if (parseFloat(balance) < parseFloat(amount)) {
      throw new Error(`Insufficient balance. Have: ${balance}, Need: ${amount}`)
    }

    // 3. Execute deposit with timeout
    const txHash = await Promise.race([
      client.deposit(chain, token, amount),
      new Promise((_, reject) => 
        setTimeout(() => reject(new Error('Transaction timeout')), 60000)
      )
    ])

    return { success: true, txHash }

  } catch (error) {
    console.error('Deposit error:', error)
    
    // Handle specific error types
    if (error.message.includes('insufficient funds')) {
      return { success: false, error: 'Insufficient ETH for gas fees' }
    } else if (error.message.includes('allowance')) {
      return { success: false, error: 'Token approval failed' }
    } else {
      return { success: false, error: error.message }
    }
  }
}
```

## Environment Setup

Create a `.env` file:

```bash
# RPC Endpoints (keep these secure)
RARI_ENDPOINT=https://rari.caff.testnet.espresso.network
APPCHAIN_ENDPOINT=https://appchain.caff.testnet.espresso.network  
RISE_SEPOLIA_ENDPOINT=https://indexing.testnet.riselabs.xyz/
ARBITRUM_SEPOLIA_ENDPOINT=https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY

# Optional: For testing
TEST_PRIVATE_KEY=0x...
```

## Supported Networks & Tokens

| Source Chain | Tokens | ChainBalanceManager |
|-------------|--------|-------------------|
| **Appchain Testnet** | USDT, WETH, WBTC | `0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7` |
| **Rise Sepolia** | USDT, WETH, WBTC | `0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745` |  
| **Arbitrum Sepolia** | USDT, WETH, WBTC | `0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A` |

**Destination (Rari Testnet):**
- BalanceManager: `0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5`
- Synthetic Tokens: gsUSDT, gsWETH, gsWBTC

## Common Patterns

### Multi-Chain Deposit

```typescript
// Deposit from multiple chains simultaneously
async function diversifiedDeposit(client) {
  const deposits = [
    client.deposit('arbitrumSepolia', 'USDT', '100'),
    client.deposit('appchain', 'WETH', '1'),
    client.deposit('riseSepolia', 'WBTC', '0.01')
  ]
  
  const results = await Promise.allSettled(deposits)
  console.log('Deposit results:', results)
}
```

### Portfolio Rebalancing

```typescript
async function rebalancePortfolio(client) {
  const portfolio = await client.getPortfolio()
  
  // Logic to rebalance between chains
  // E.g., if too much on one chain, withdraw and deposit elsewhere
}
```

## Security Considerations

1. **Private Key Management**: Never expose private keys in frontend code
2. **Amount Validation**: Always validate amounts client-side
3. **Gas Estimation**: Check gas prices before transactions
4. **Error Recovery**: Implement retry logic for failed transactions
5. **Cross-Chain Timing**: Account for 1-2 minute delays for cross-chain messages

## Troubleshooting

### Common Issues

**"Insufficient balance" errors:**
- Check if user has enough tokens AND ETH for gas
- Verify token is whitelisted on the source chain

**"Transaction timeout" errors:** 
- Network congestion - retry with higher gas prices
- RPC endpoint issues - try different endpoint

**Cross-chain delays:**
- Hyperlane relayers take 1-2 minutes typically
- Check Hyperlane explorer for message status

### Debug Mode

```typescript
// Enable detailed logging
const client = new CrossChainCLOBClient(privateKey, { debug: true })
```

For more examples and advanced usage, see the `/examples` directory.