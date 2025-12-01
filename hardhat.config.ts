import { HardhatUserConfig } from 'hardhat/types';
import '@nomicfoundation/hardhat-toolbox';
import '@nomicfoundation/hardhat-foundry';
import '@openzeppelin/hardhat-upgrades';
import 'hardhat-deploy';
import 'dotenv/config';

const localhost = process.env.FORK_NODE_URL || 'http://localhost:8545';

function getChainId(nodeUrl: string) {
  if (['eth-mainnet', 'mainnet.infura'].some((v) => nodeUrl.includes(v))) {
    return 1;
  }

  if (['testnet.rpc.hemi', 'hemi-testnet'].some((v) => nodeUrl.includes(v))) {
    return 743111;
  }

  if (['hemi.network', 'hemi.drpc'].some((v) => nodeUrl.includes(v))) {
    return 43111;
  }

  return 31337;
}

function getFork() {
  const nodeUrl = process.env.FORK_NODE_URL;
  return nodeUrl
    ? {
        initialBaseFeePerGas: 0,
        forking: {
          url: nodeUrl,
          blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
        },
        chainId: getChainId(nodeUrl),
      } // eslint-disable-next-line @typescript-eslint/no-explicit-any
    : ({} as any);
}

let accounts;
if (process.env.MNEMONIC) {
  accounts = { mnemonic: process.env.MNEMONIC };
}

if (process.env.PRIVATE_KEY) {
  accounts = [process.env.PRIVATE_KEY];
}

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: getFork(),
    localhost: {
      accounts,
      saveDeployments: true,
      chainId: getChainId(localhost),
      autoImpersonate: true,
    },
    ethereum: {
      url: process.env.ETHEREUM_NODE_URL || '',
      chainId: 1,
      accounts,
    },
    hemi: {
      url: process.env.HEMI_NODE_URL || '',
      chainId: 43111,
      accounts,
    },
    hemi_testnet: {
      url: process.env.HEMI_TESTNET_NODE_URL || '',
      chainId: 743111,
      accounts,
    },
  },

  sourcify: {
    enabled: false,
  },

  blockscout: {
    enabled: true,
    customChains: [
      {
        network: 'hemi',
        chainId: 43111,
        urls: {
          apiURL: 'https://explorer.hemi.xyz/api',
          browserURL: 'https://explorer.hemi.xyz',
        },
      },
      {
        network: 'hemi_testnet',
        chainId: 743111,
        urls: {
          apiURL: 'https://testnet.explorer.hemi.xyz/api',
          browserURL: 'https://testnet.explorer.hemi.xyz',
        },
      },
    ],
  },

  etherscan: {
    enabled: false,
    apiKey: process.env.ETHERSCAN_API_KEY,
  },

  namedAccounts: {
    deployer: process.env.DEPLOYER || 0,
  },

  solidity: {
    version: '0.8.30',
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
    },
  },
};

export default config;
