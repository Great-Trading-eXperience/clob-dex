import { index, onchainTable } from "ponder";

export const orderStatusEnum = {
  open: "Open",
  cancelled: "Cancelled",
  filled: "Filled",
};

const orderSchema = (t: any) => ({
  user: t.hex(),
  coin: t.varchar(),
  side: t.varchar(),
  timestamp: t.integer(),
  price: t.bigint(),
  quantity: t.bigint(),
  orderValue: t.bigint(),
  filled: t.bigint(),
  type: t.varchar(),
  status: t.varchar(),
});

const orderIndexes = (table: any) => ({
  coinIdx: index().on(table.coin),
  userIdx: index().on(table.user),
  sideIdx: index().on(table.side),
});

export const orders = onchainTable("orders", (t: any) => ({
  id: t.bigint().primaryKey(),
  ...orderSchema(t),
  expiry: t.integer(),
  isActive: t.boolean(),
}), (table: any) => ({
  ...orderIndexes(table),
  isActiveIdx: index().on(table.isActive),
}));

export const orderHistory = onchainTable("order_history", (t: any) => ({
  id: t.text().primaryKey(),
  orderId: t.bigint(),
  ...orderSchema(t),
}), (table: any) => ({
  orderIdIdx: index().on(table.orderId),
  ...orderIndexes(table),
}));

export const trades = onchainTable("trades", (t) => ({
  id: t.text().primaryKey(),
  transactionId: t.text(),
  user: t.hex(),
  coin: t.varchar(),
  side: t.varchar(),
  price: t.bigint(),
  quantity: t.bigint(),
  tradeValue: t.bigint(),
  fee: t.bigint(),
  pnl: t.bigint(),
  timestamp: t.integer(),
}),
  (table) => ({
    coinIdx: index().on(table.coin),
    userIdx: index().on(table.user),
    sideIdx: index().on(table.side),
    transactionIdx: index().on(table.transactionId),
  })
);

export const orderPlacedEvents = onchainTable("order_placed_events", (t) => ({
  id: t.text().primaryKey(),
  orderId: t.bigint(),
  user: t.hex(),
  side: t.varchar(),
  price: t.bigint(),
  quantity: t.bigint(),
  timestamp: t.integer(),
  type: t.varchar(),
})
  ,
  (table) => ({
    orderIdIdx: index().on(table.orderId),
    userIdx: index().on(table.user),
    sideIdx: index().on(table.side),
  })
);

export const orderMatchedEvents = onchainTable("order_matched_events", (t) => ({
  id: t.text().primaryKey(),
  transactionId: t.text(),
  user: t.hex(),
  buyOrderId: t.bigint(),
  sellOrderId: t.bigint(),
  timestamp: t.integer(),
  price: t.bigint(),
  quantity: t.bigint(),
  side: t.varchar(),
}),
  (table) => ({
    buyOrderIdIdx: index().on(table.buyOrderId),
    userIdx: index().on(table.user),
    sellOrderIdIdx: index().on(table.sellOrderId),
    transactionIdx: index().on(table.transactionId),
  }));

export const orderCancelledEvents = onchainTable("order_cancelled_events", (t) => ({
  id: t.text().primaryKey(),
  orderId: t.bigint(),
  user: t.hex(),
  side: t.varchar(),
  price: t.bigint(),
  remainingQuantity: t.bigint(),
  timestamp: t.integer(),
}),
  (table) => ({
    orderIdIdx: index().on(table.orderId),
    userIdx: index().on(table.user),
    sideIdx: index().on(table.side),
  }));



