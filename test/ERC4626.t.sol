// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.30;

import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {YieldVault} from "src/YieldVault.sol";
import {Constants} from "test/helpers/Constants.sol";

contract ERC4626StdTest is ERC4626Test {
    function setUp() public override {
        _underlying_ = address(new ERC20Mock());

        YieldVault _vault = new YieldVault();
        // clear storage to initialize vault
        vm.store(address(_vault), Constants.INITIALIZABLE_STORAGE, bytes32(uint256(0)));
        _vault.initialize("Yield Vault", "yieldVault", address(_underlying_), address(this));

        _vault_ = address(_vault);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = true;
    }
}
