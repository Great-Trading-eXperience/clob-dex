/**
 * Cross-Chain CLOB DEX Deployed Contracts
 * Updated with real deployment addresses and imported ABIs
 */

import {
	ChainBalanceManagerABI,
	BalanceManagerABI,
	ERC20ABI,
	TokenRegistryABI,
	SyntheticTokenABI,
	SyntheticTokenFactoryABI,
	ChainRegistryABI,
	PoolManagerABI,
	GTXRouterABI,
	OrderBookABI,
	UpgradeableBeaconABI,
	BeaconProxyABI,
} from "./abis";

interface ContractDetails {
	address: string;
	abi: any[];
	inheritedFunctions?: any;
}

interface DeployedContracts {
	[chainId: string]: {
		[contractName: string]: ContractDetails;
	};
}

export const deployedContracts: DeployedContracts = {
	// Rari Testnet (Destination Chain)
	1918988905: {
		BalanceManager: {
			address: "0xd7fEF09a6cBd62E3f026916CDfE415b1e64f4Eb5",
			abi: BalanceManagerABI,
		},
		PoolManager: {
			address: "0xA3B22cA94Cc3Eb8f6Bd8F4108D88d085e12d886b",
			abi: PoolManagerABI,
		},
		TokenRegistry: {
			address: "0x80207B9bacc73dadAc1C8A03C6a7128350DF5c9E",
			abi: TokenRegistryABI,
		},
		SyntheticTokenFactory: {
			address: "0x2594C4ca1B552ad573bcc0C4c561FAC6a87987fC",
			abi: SyntheticTokenFactoryABI,
		},
		ChainRegistry: {
			address: "0x0a1Ced1539C9FB81aBdDF870588A4fEfBf461bBB",
			abi: ChainRegistryABI,
		},
		gsUSDC: {
			address: "0x6fcf28b801C7116cA8b6460289e259aC8D9131F3",
			abi: SyntheticTokenABI,
		},
		gsWETH: {
			address: "0xC7A1777e80982E01e07406e6C6E8B30F5968F836",
			abi: SyntheticTokenABI,
		},
		gsWBTC: {
			address: "0xfAcf2E43910f93CE00d95236C23693F73FdA3Dcf",
			abi: SyntheticTokenABI,
		},
		Router: {
			address: "0xF38489749c3e65c82a9273c498A8c6614c34754b",
			abi: GTXRouterABI,
		},
		BalanceManagerBeacon: {
			address: "0xF1A53bC852bB9e139a8200003B55164592695395",
			abi: UpgradeableBeaconABI,
		},
		PoolManagerBeacon: {
			address: "0x6F97F295D78373FE7555Fd809f3Bb5c146cC8CF7",
			abi: UpgradeableBeaconABI,
		},
		RouterBeacon: {
			address: "0x00BF70ab9Fb9f330E9Bb66d6E3A11F8Cf51F737a",
			abi: UpgradeableBeaconABI,
		},
		OrderBookBeacon: {
			address: "0xa8630B75d92814b79dE1C5A170d00Ef0714b3C28",
			abi: UpgradeableBeaconABI,
		},
	},

	// Appchain Testnet (Source Chain)
	4661: {
		ChainBalanceManager: {
			address: "0x27D0Dd86F00b59aD528f1D9B699847A588fbA2C7",
			abi: ChainBalanceManagerABI,
		},
		USDC: {
			address: "0x1362Dd75d8F1579a0Ebd62DF92d8F3852C3a7516",
			abi: ERC20ABI,
		},
		WETH: {
			address: "0x02950119C4CCD1993f7938A55B8Ab8384C3CcE4F",
			abi: ERC20ABI,
		},
		WBTC: {
			address: "0xb2e9Eabb827b78e2aC66bE17327603778D117d18",
			abi: ERC20ABI,
		},
	},

	// Arbitrum Sepolia (Source Chain)
	421614: {
		ChainBalanceManager: {
			address: "0xF36453ceB82F0893FCCe4da04d32cEBfe33aa29A",
			abi: ChainBalanceManagerABI,
		},
		USDC: {
			address: "0x5eafC52D170ff391D41FBA99A7e91b9c4D49929a",
			abi: ERC20ABI,
		},
		WETH: {
			address: "0x6B4C6C7521B3Ed61a9fA02E926b73D278B2a6ca7",
			abi: ERC20ABI,
		},
		WBTC: {
			address: "0x24E55f604FF98a03B9493B53bA3ddEbD7d02733A",
			abi: ERC20ABI,
		},
	},

	// Rise Sepolia (Source Chain)
	11155931: {
		ChainBalanceManager: {
			address: "0xa2B3Eb8995814E84B4E369A11afe52Cef6C7C745",
			abi: ChainBalanceManagerABI,
		},
		USDC: {
			address: "0x97668AEc1d8DEAF34d899c4F6683F9bA877485f6",
			abi: ERC20ABI,
		},
		WETH: {
			address: "0x567a076BEEF17758952B05B1BC639E6cDd1A31EC",
			abi: ERC20ABI,
		},
		WBTC: {
			address: "0xc6b3109e45F7A479Ac324e014b6a272e4a25bF0E",
			abi: ERC20ABI,
		},
	},
} as const;
