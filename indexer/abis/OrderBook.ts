export const OrderBookABI = [
  {
    "type": "function",
    "name": "cancelOrder",
    "inputs": [
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum Side"
      },
      {
        "name": "price",
        "type": "uint64",
        "internalType": "Price"
      },
      {
        "name": "orderId",
        "type": "uint48",
        "internalType": "OrderId"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getBestPrice",
    "inputs": [
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct IOrderBook.PriceVolume",
        "components": [
          {
            "name": "price",
            "type": "uint64",
            "internalType": "Price"
          },
          {
            "name": "volume",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getNextBestPrices",
    "inputs": [
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum Side"
      },
      {
        "name": "price",
        "type": "uint64",
        "internalType": "Price"
      },
      {
        "name": "count",
        "type": "uint8",
        "internalType": "uint8"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple[]",
        "internalType": "struct IOrderBook.PriceVolume[]",
        "components": [
          {
            "name": "price",
            "type": "uint64",
            "internalType": "Price"
          },
          {
            "name": "volume",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getOrderQueue",
    "inputs": [
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum Side"
      },
      {
        "name": "price",
        "type": "uint64",
        "internalType": "Price"
      }
    ],
    "outputs": [
      {
        "name": "orderCount",
        "type": "uint48",
        "internalType": "uint48"
      },
      {
        "name": "totalVolume",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getUserActiveOrders",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple[]",
        "internalType": "struct IOrderBook.Order[]",
        "components": [
          {
            "name": "id",
            "type": "uint48",
            "internalType": "OrderId"
          },
          {
            "name": "user",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "next",
            "type": "uint48",
            "internalType": "OrderId"
          },
          {
            "name": "prev",
            "type": "uint48",
            "internalType": "OrderId"
          },
          {
            "name": "timestamp",
            "type": "uint48",
            "internalType": "uint48"
          },
          {
            "name": "expiry",
            "type": "uint48",
            "internalType": "uint48"
          },
          {
            "name": "price",
            "type": "uint64",
            "internalType": "Price"
          },
          {
            "name": "quantity",
            "type": "uint128",
            "internalType": "Quantity"
          },
          {
            "name": "filled",
            "type": "uint128",
            "internalType": "Quantity"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "placeMarketOrder",
    "inputs": [
      {
        "name": "quantity",
        "type": "uint128",
        "internalType": "Quantity"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint48",
        "internalType": "OrderId"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "placeOrder",
    "inputs": [
      {
        "name": "price",
        "type": "uint64",
        "internalType": "Price"
      },
      {
        "name": "quantity",
        "type": "uint128",
        "internalType": "Quantity"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint48",
        "internalType": "OrderId"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "OrderCancelled",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint48",
        "indexed": true,
        "internalType": "OrderId"
      },
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": true,
        "internalType": "enum Side"
      },
      {
        "name": "price",
        "type": "uint64",
        "indexed": false,
        "internalType": "Price"
      },
      {
        "name": "remainingQuantity",
        "type": "uint128",
        "indexed": false,
        "internalType": "Quantity"
      },
      {
        "name": "timestamp",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OrderMatched",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "buyOrderId",
        "type": "uint48",
        "indexed": true,
        "internalType": "OrderId"
      },
      {
        "name": "sellOrderId",
        "type": "uint48",
        "indexed": true,
        "internalType": "OrderId"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum Side"
      },
      {
        "name": "timestamp",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      },
      {
        "name": "executionPrice",
        "type": "uint64",
        "indexed": false,
        "internalType": "Price"
      },
      {
        "name": "executedQuantity",
        "type": "uint128",
        "indexed": false,
        "internalType": "Quantity"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OrderPlaced",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint48",
        "indexed": true,
        "internalType": "OrderId"
      },
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": true,
        "internalType": "enum Side"
      },
      {
        "name": "price",
        "type": "uint64",
        "indexed": false,
        "internalType": "Price"
      },
      {
        "name": "quantity",
        "type": "uint128",
        "indexed": false,
        "internalType": "Quantity"
      },
      {
        "name": "timestamp",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      },
      {
        "name": "expiry",
        "type": "uint48",
        "indexed": false,
        "internalType": "uint48"
      },
      {
        "name": "isMarketOrder",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "CannotFindNextEmptyKey",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CannotFindPrevEmptyKey",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CannotInsertEmptyKey",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CannotInsertExistingKey",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CannotRemoveEmptyKey",
    "inputs": []
  },
  {
    "type": "error",
    "name": "CannotRemoveMissingKey",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPackedData",
    "inputs": []
  },
  {
    "type": "error",
    "name": "InvalidPrice",
    "inputs": [
      {
        "name": "price",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "InvalidQuantity",
    "inputs": []
  },
  {
    "type": "error",
    "name": "OrderNotFound",
    "inputs": []
  },
  {
    "type": "error",
    "name": "QueueEmpty",
    "inputs": []
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "UnauthorizedCancellation",
    "inputs": []
  }
] as const;