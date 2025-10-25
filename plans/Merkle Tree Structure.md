Merkle Tree Structure (Scales infinitely):

Leaf = hash(user, totalUSDValue)

Example with 3 tokens:
├─ Leaf 1: hash(Alice, $1500)  // She holds mix of gUSDC + gETH + gWBTC
├─ Leaf 2: hash(Bob, $3000)    // He holds different mix
└─ Leaf 3: hash(Charlie, $2500)

Example with 10 tokens:
├─ Leaf 1: hash(Alice, $1500)  // SAME structure!
├─ Leaf 2: hash(Bob, $3000)    // Still just user + USD value
└─ Leaf 3: hash(Charlie, $2500)

The leaf is ALWAYS just: (user address, total USD value)
✅ Doesn't matter if you have 3 tokens or 100 tokens!