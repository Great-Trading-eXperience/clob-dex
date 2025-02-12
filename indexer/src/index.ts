import { randomUUID } from "crypto";
import { ponder } from "ponder:registry";
import { orderHistory, orderMatchedEvents, orderPlacedEvents, orders, orderStatusEnum, trades } from "ponder:schema";
import { keccak256 } from "viem";


interface OrderData {
    id: string;
    orderId: bigint;
    user: `0x${string}`;
    side: string;
    price: bigint;
    quantity: bigint;
    timestamp: number;
    expiry?: number;
    type: string;
}

interface OrderHistoryEntry {
    id: string;
    orderId?: bigint;
    user: `0x${string}`;
    coin: string;
    side: string;
    price: bigint;
    quantity: bigint;
    orderValue?: bigint;
    filled?: bigint;
    type?: string;
    status?: string;
    fee?: bigint;
    pnl?: bigint;
    timestamp: number;
}

async function createOrderHistoryEntry(data: OrderData, additionalData: Partial<OrderHistoryEntry> & { transactionId?: string } = {}): Promise<OrderHistoryEntry> {
    return {
        id: data.id,
        user: data.user,
        coin: "ETH/USDC", //TODO: Make configurable
        side: data.side,
        price: data.price,
        quantity: data.quantity,
        timestamp: data.timestamp,
        ...additionalData
    };
}

ponder.on("OrderBook:OrderPlaced", async ({ event, context }) => {
    const orderData: OrderData = {
        id: event.transaction.hash,
        orderId: BigInt(event.args.orderId),
        user: event.args.user,
        side: event.args.side ? 'Sell' : 'Buy',
        price: BigInt(event.args.price),
        quantity: BigInt(event.args.quantity),
        timestamp: Number(event.args.timestamp),
        expiry: Number(event.args.expiry),
        type: event.args.isMarketOrder ? 'Market' : 'Limit',
    };

    await context.db.insert(orderPlacedEvents).values(orderData).onConflictDoNothing();

    if (!event.args.isMarketOrder) {
        await context.db.insert(orders).values({
            id: BigInt(event.args.orderId),
            user: event.args.user,
            coin: "ETH/USDC", //TODO: Make configurable
            side: event.args.side ? 'Sell' : 'Buy',
            price: BigInt(event.args.price),
            quantity: BigInt(event.args.quantity),
            orderValue: BigInt(event.args.price) * BigInt(event.args.quantity),
            filled: BigInt(0),
            type: 'Limit',
            status: orderStatusEnum.open,
            expiry: Number(event.args.expiry),
            isActive: true,
            timestamp: Number(event.args.timestamp),
        }).onConflictDoNothing();
    }

    const orderValue = orderData.price * orderData.quantity;
    const historyEntry = await createOrderHistoryEntry(orderData, {
        orderId: orderData.orderId,
        orderValue,
        filled: BigInt(0),
        type: event.args.isMarketOrder ? 'Market' : 'Limit',
        status: event.args.isMarketOrder ? '' : orderStatusEnum.open //TODO: check case when market order is placed
    });

    await context.db.insert(orderHistory).values(historyEntry).onConflictDoNothing();
});

ponder.on("OrderBook:OrderMatched", async ({ event, context }) => {
    const matchData = {
        id: randomUUID(),
        transactionId: event.transaction.hash,
        user: event.args.user,
        buyOrderId: BigInt(event.args.buyOrderId),
        sellOrderId: BigInt(event.args.sellOrderId),
        price: BigInt(event.args.executionPrice),
        quantity: BigInt(event.args.executedQuantity),
        timestamp: Number(event.args.timestamp),
        side: event.args.side ? 'Sell' : 'Buy',
    };

    await context.db.insert(orderMatchedEvents).values(matchData).onConflictDoNothing();

    const updateMatchedOrder = async (orderId: bigint, existingOrder: any) => {
        const newFilled = BigInt(existingOrder.filled) + matchData.quantity;
        const newStatus = newFilled === existingOrder.quantity ? orderStatusEnum.filled : orderStatusEnum.open;

        await context.db.update(orders, { id: orderId }).set({
            filled: newFilled,
            status: newStatus,
            isActive: newStatus === orderStatusEnum.open,
        });

        const trade = await createOrderHistoryEntry({
            id: randomUUID(),
            orderId,
            user: existingOrder.user,
            side: existingOrder.side,
            price: existingOrder.price,
            quantity: matchData.quantity,
            timestamp: matchData.timestamp,
            type: existingOrder.type,
        }, {
            transactionId: event.transaction.hash,
            orderValue: matchData.price * matchData.quantity,
            fee: BigInt(0), //TODO
            pnl: BigInt(0), //TODO
        });

        await context.db.insert(trades).values(trade).onConflictDoNothing();
    }

    const buyOrder = await context.db.find(orders, { id: matchData.buyOrderId });
    const sellOrder = await context.db.find(orders, { id: matchData.sellOrderId });

    if (buyOrder) await updateMatchedOrder(matchData.buyOrderId, buyOrder);
    if (sellOrder) await updateMatchedOrder(matchData.sellOrderId, sellOrder);
});


// ponder.on("OrderBook:OrderCancelled", async ({ event, context }) => {
//     const cancelData: OrderData = {
//         id: event.transaction.hash,
//         orderId: BigInt(event.args.orderId),
//         user: event.args.user,
//         side: event.args.side ? 'Buy' : 'Sell',
//         price: BigInt(event.args.price),
//         quantity: BigInt(event.args.remainingQuantity),
//         timestamp: Number(event.args.timestamp),
//         type: event.args.isMarketOrder ? 'Market' : 'Limit',

//     };

//     await context.db.insert(orderCancelledEvents).values({
//         ...cancelData,
//         remainingQuantity: cancelData.quantity,
//     }).onConflictDoNothing();

//     await context.db.update(orders, {
//         orderId: cancelData.orderId,
//     }).set({
//         status: orderStatusEnum.cancelled,
//         isActive: false,
//     });

//     const historyEntry = await createOrderHistoryEntry(cancelData, {
//         orderId: cancelData.orderId,
//         orderValue: cancelData.price * cancelData.quantity,
//         filled: BigInt(0),
//         status: orderStatusEnum.cancelled,
//     });

//     await context.db.insert(orderHistory).values(historyEntry).onConflictDoNothing();
// });