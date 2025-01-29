# CLOB DEX - Decentralized Central Limit Order Book

A high-performance, fully on-chain Central Limit Order Book (CLOB) implementation with price-time priority matching algorithm.

## Core Features

### Order Management
- **Limit Orders**: Place orders with specific price and quantity
- **Market Orders**: Immediate execution at best available prices
- **Order Cancellation**: Users can cancel their active orders
- **Reentrancy Protection**: All order operations are protected against reentrancy attacks

### Order Matching
- Price-time priority matching algorithm
- Cross-matching between buy and sell orders
- Support for partial fills
- Real-time order execution

### Order Book Structure
- **Price Tree**: Red-Black Tree implementation for efficient price level management
  - O(log n) operations for inserting/removing price levels
  - Quick access to best bid/ask prices
  - Ordered iteration through price levels

- **Order Queue**:
  - Double-linked list for order storage at each price level
  - FIFO (First In, First Out) execution within same price level
  - Efficient order removal and updates

### Data Storage Optimization
- **Order Packing**: Compact order storage using bit manipulation
  ```solidity
  Side (1 bytes) | Price (64 bytes) | OrderId (48 bytes)
  ```
- **Active Order Tracking**: Per-user order tracking using EnumerableSet
- **Price Level Management**: Automatic cleanup of empty price levels

### Key Data Structures

```solidity
// Price Tree Mapping
mapping(Side => RBTree.Tree) private priceTrees;

// Order Queues at Each Price Level
mapping(Side => mapping(Price => OrderQueueLib.OrderQueue)) private orderQueues;

// User's Active Orders
mapping(address => EnumerableSet.UintSet) private activeUserOrders;
```

### View Functions
- Get best bid/ask prices
- View order queue status at any price level
- Retrieve user's active orders
- Get next best price levels with volumes

## Gas Optimization Techniques

1. **Efficient Storage**
   - Minimal storage operations
   - Packed order data
   - Optimized mappings

2. **Smart Data Structures**
   - Red-Black Tree for price levels (O(log n) operations)
   - Double-linked lists for order management
   - EnumerableSet for tracking active orders

3. **Memory Management**
   - Strategic use of memory vs storage
   - Optimized array operations
   - Efficient event emission

## Security Features

1. **Access Control**
   - Order cancellation restricted to order owner
   - Reentrancy protection on all state-modifying functions

2. **Input Validation**
   - Price and quantity validation
   - Order existence checks
   - Price level integrity checks

3. **State Management**
   - Atomic operations
   - Consistent state updates
   - Automatic cleanup of empty states
