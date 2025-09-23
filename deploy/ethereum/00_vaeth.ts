import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigurePool } from "../../helpers/deploy-helpers";
import { vaETH, VESPER_POOL } from "../../helpers/deploy-config";
import Addresses from "../../helpers/address";

const poolAlias = vaETH[1]; // pool symbol

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigurePool({
    alias: poolAlias,
    contract: VESPER_POOL,
    proxy: {
      initializeArgs: [...vaETH, Address.WETH],
    },
  });
};

func.tags = [poolAlias];
export default func;
