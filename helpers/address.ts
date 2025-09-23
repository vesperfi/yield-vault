import hre from "hardhat";

const A = {
  ethereum: {
    GNOSIS_SAFE: "0x9520b477Aa81180E6DdC006Fc09Fb6d3eb4e807A",
    ETH: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    WETH: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    DAI: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
    USDC: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    WBTC: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    VSP: "0x1b40183EFB4Dd766f11bDa7A7c3AD8982e998421",
    stETH: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
    wstETH: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
    rETH: "0xae78736Cd615f374D3085123A210448E74Fc6393",
    cbETH: "0xBe9895146f7AF43049ca1c1AE358B0541Ea49704",
    FRAX: "0x853d955aCEf822Db058eb8505911ED77F175b99e",
    masterOracle: "0x80704Acdf97723963263c78F861F091ad04F46E2",
    swapper: "0x229f19942612A8dbdec3643CB23F88685CCd56A5",
    Vesper: {
      poolKeeper: "0xc6b8ed2b369A5fEfd2A0d7cbdBF8aC920DBa3906",
      poolMaintainer: "0x70AB149e550690D55a46AA326211438c5D47B6D3",
    },
  },
  optimism: {
    GNOSIS_SAFE: "0x32934AD7b1121DeFC631080b58599A0eaAB89878",
    WETH: "0x4200000000000000000000000000000000000006",
    OP: "0x4200000000000000000000000000000000000042",
    USDC: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85",
    USDCe: "0x7F5c764cBc14f9669B88837ca1490cCa17c31607",
    WBTC: "0x68f180fcCe6836688e9084f035309E29Bf0A2095",
    masterOracle: "0x0aac835162D368F246dc71628AfcD6d2930c47d3",
    swapper: "0x017CBF62b53313d5eE3aD1288daA95CD39AA11fE",
    Vesper: {
      poolKeeper: "0x68c80d3d6567B5998F78aC0c81467D5d4A82E781",
      poolMaintainer: "0x8Db4A31683f0B8af64efe13C0D304da6fccFcE13",
    },
  },
  base: {
    GNOSIS_SAFE: "0x32934AD7b1121DeFC631080b58599A0eaAB89878",
    WETH: "0x4200000000000000000000000000000000000006",
    USDC: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    cbETH: "0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22",
    wstETH: "0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452",
    masterOracle: "0x99866a6074ADb027f09c9AF31929dB5941D36DA7",
    swapper: "0xd7c751fA32590451548B100C4f6442F062C9bc8E",
    Vesper: {
      poolKeeper: "0x33Aa8F94428C0F891dFd77DD141878aBCaEFEbe8",
      poolMaintainer: "0x017CBF62b53313d5eE3aD1288daA95CD39AA11fE",
    },
  },
};

const chains = {
  1: "ethereum",
  31337: "ethereum",
  10: "optimism",
  8453: "base",
};

const getChain = (): string => {
  const { chainId } = hre.network.config;

  const chain = chains[chainId!];

  if (!chain) {
    throw Error(`No address setup for chainId ${chainId}`);
  }

  return chain;
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const Address = (A as { [key: string]: any })[getChain()];

export default A;
