import { DeployFunction } from "hardhat-deploy/types";
import { YIELD_VAULT, YIELD_VAULT_FACTORY } from "../../helpers/deploy-config";

const func: DeployFunction = async function (hre) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, get, log } = deployments;
  const { deployer } = await getNamedAccounts();

  if (!deployer) {
    throw Error(`The 'deployer' named account wasn't set`);
  }

  // Get YieldVault implementation address (should be deployed by 00_implementation.ts)
  const implementationAlias = `${YIELD_VAULT}_Implementation`;
  const implementationDeployment = await get(implementationAlias);
  const implementationAddress = implementationDeployment.address;

  log(`Using YieldVault implementation at: ${implementationAddress}`);

  // Deploy YieldVaultFactory
  const factoryAlias = YIELD_VAULT_FACTORY;
  const factoryDeployment = await deploy(factoryAlias, {
    contract: YIELD_VAULT_FACTORY,
    from: deployer,
    log: true,
    args: [implementationAddress, deployer], // Factory constructor takes implementation address and owner
  });

  log(`YieldVaultFactory deployed at: ${factoryDeployment.address}`);
  log(`Factory implementation: ${implementationAddress}`);
};

func.tags = ["YieldVaultFactory"];
func.dependencies = ["YieldVaultImplementation"]; // Depends on implementation deployment

export default func;
