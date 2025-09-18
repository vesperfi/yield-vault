import { HardhatUserConfig } from 'hardhat/types'
import '@nomicfoundation/hardhat-toolbox'
import '@nomicfoundation/hardhat-foundry'
import '@openzeppelin/hardhat-upgrades'
import 'hardhat-deploy'
import 'dotenv/config'

const localhost = process.env.FORK_NODE_URL || 'http://localhost:8545'
const ethereumNodeUrl = process.env.ETHEREUM_NODE_URL || ''

function getChainConfig(nodeUrl: string) {
  if (['eth-mainnet', 'mainnet.infura'].some((v) => nodeUrl.includes(v))) {
    return { chainId: 1, deploy: ['deploy/ethereum'] }
  }

  return { chainId: 31337, deploy: ['deploy/ethereum'] }
}

function getFork() {
  const nodeUrl = process.env.FORK_NODE_URL
  return nodeUrl
    ? {
        initialBaseFeePerGas: 0,
        forking: {
          url: nodeUrl,
          blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
        },
        ...getChainConfig(nodeUrl),
      } // eslint-disable-next-line @typescript-eslint/no-explicit-any
    : ({} as any)
}

let accounts
if (process.env.MNEMONIC) {
  accounts = { mnemonic: process.env.MNEMONIC }
}

if (process.env.PRIVATE_KEY) {
  accounts = [process.env.PRIVATE_KEY]
}

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: getFork(),
    localhost: {
      accounts,
      saveDeployments: true,
      ...getChainConfig(localhost),
      autoImpersonate: true,
    },
    ethereum: {
      url: ethereumNodeUrl,
      accounts,
      ...getChainConfig(ethereumNodeUrl),
    },
  },

  sourcify: {
    enabled: false,
  },

  etherscan: {
    enabled: true,
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
}

export default config
