import { DeployFunction } from "hardhat-deploy/types";
import { YIELD_VAULT } from "../../helpers/deploy-config";

const func: DeployFunction = async function (hre) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy, get, getOrNull, log } = deployments;
  const { deployer } = await getNamedAccounts();

  if (!deployer) {
    throw Error(`The 'deployer' named account wasn't set`);
  }

  // Deploy YieldVault implementation
  const implementationAlias = `${YIELD_VAULT}_Implementation`;

  // Check if already deployed
  const existingImplementation = await getOrNull(implementationAlias);
  if (existingImplementation) {
    log(`YieldVault implementation already deployed at: ${existingImplementation.address}`);
    return;
  }

  // Deploy new implementation
  const implementationDeployment = await deploy(implementationAlias, {
    contract: YIELD_VAULT,
    from: deployer,
    log: true,
    args: [], // YieldVault constructor takes no arguments
  });

  log(`✓ YieldVault implementation deployed at: ${implementationDeployment.address}`);
  log(`  Contract: ${YIELD_VAULT}`);
  log(`  Alias: ${implementationAlias}`);
};

func.tags = ["YieldVaultImplementation"];
func.dependencies = []; // No dependencies

export default func;
