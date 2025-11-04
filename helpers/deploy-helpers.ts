import hre from "hardhat";
import chalk from "chalk";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { saveForSafeBatchExecution } from "./safe";
import { deploy, DeployParams } from "./deploy";
import { Address } from "./address";

type ConfigParams = {
  keeper?: string;
  maintainer?: string;
};

export const executeOrStoreTxIfMultisig = async (
  hre: HardhatRuntimeEnvironment,
  executeFunction: () => Promise<unknown>,
): Promise<void> => {
  const { deployments } = hre;
  const { catchUnknownSigner } = deployments;

  const multisigTx = await catchUnknownSigner(executeFunction, { log: true });

  if (multisigTx) {
    console.log(
      chalk.yellow("Note: Current wallet cannot execute transaction. It will be executed by safe later in the flow."),
    );
    await saveForSafeBatchExecution(multisigTx);
  }
};

export const deployAndConfigurePool = async (deployParams: DeployParams, configParams?: ConfigParams) => {
  const { execute, read } = hre.deployments;
  const { alias } = deployParams;

  // deploy vault, proxy and initialize proxy
  const deployed = await deploy(hre, deployParams);
  const poolAddress = deployed.address;

  // Add keeper
  const governor = await read(alias, "governor");
  const keeper = configParams?.keeper || Address.Vesper.poolKeeper;
  const keepers = await read(alias, "keepers");
  if (!keepers.includes(hre.ethers.getAddress(keeper))) {
    const executeFunction = () => execute(alias, { from: governor, log: true }, "addKeeper", keeper);
    await executeOrStoreTxIfMultisig(hre, executeFunction);
  }

  // Add maintainer
  const maintainer = configParams?.maintainer || Address.Vesper.poolMaintainer;
  const maintainers = await read(alias, "maintainers");
  if (!maintainers.includes(hre.ethers.getAddress(maintainer))) {
    const executeFunction = () => execute(alias, { from: governor, log: true }, "addMaintainer", maintainer);
    await executeOrStoreTxIfMultisig(hre, executeFunction);
  }

  if (!["hardhat", "localhost"].includes(hre.network.name)) {
    await hre.run("verify:verify", { address: poolAddress });
  }
};
