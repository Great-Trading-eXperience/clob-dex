import { createConfig } from "ponder";
import { http } from "viem";
import { OrderBookABI } from "./abis/OrderBook";


export default createConfig({
  database: {
    kind: "postgres",
    connectionString: process.env.PONDER_DATABASE_URL,
  },
  networks: {
    anvil: {
      chainId: 31337,
      transport: http("http://127.0.0.1:8545"),
      disableCache: true,
    },
    // riseSepolia: {
    //   chainId: 11155931,
    //   transport: http(process.env.PONDER_RPC_URL_RISE_SEPOLIA),
    //   pollingInterval: 5000,
    //   maxRequestsPerSecond: 10,
    // }
  },
  contracts: {
    OrderBook: {
      abi: OrderBookABI,
      address: "0x49fd2be640db2910c2fab69bb8531ab6e76127ff",
      // startBlock: 120991305,
      network: "anvil",
    },
  },
});
