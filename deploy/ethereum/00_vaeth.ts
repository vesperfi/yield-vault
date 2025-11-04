import { DeployFunction } from "hardhat-deploy/types";
import { deployAndConfigurePool } from "../../helpers/deploy-helpers";
import { vaETH, YIELD_VAULT } from "../../helpers/deploy-config";
import Addresses from "../../helpers/address";

const alias = vaETH[1]; // vault symbol

const func: DeployFunction = async function () {
  const Address = Addresses.ethereum;

  await deployAndConfigurePool({
    alias,
    contract: YIELD_VAULT,
    proxy: {
      initializeArgs: [...vaETH, Address.WETH],
    },
  });
};

func.tags = [alias];
export default func;
