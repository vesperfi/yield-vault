// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "src/YieldVault.sol";

import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants} from "test/helpers/Constants.sol";

contract YieldVaultTestBase is Test {
    YieldVault vault;
    MockERC20 asset;
    address alice = makeAddr("alice");
    address feeCollector = makeAddr("feeCollector");
    address strategy = makeAddr("strategy");
    uint256 debtRatio = 9_000;
    address strategy2 = makeAddr("strategy2");
    uint256 debtRatio2 = 1_000;
    uint256 assetUnit;

    function setUp() public {
        vault = new YieldVault();
        asset = new MockERC20();
        assetUnit = 10 ** asset.decimals();
        // clear storage to initialize vault
        vm.store(address(vault), Constants.INITIALIZABLE_STORAGE, bytes32(uint256(0)));
        vault.initialize("Yield Vault", "yieldVault", address(asset), address(this));
    }

    /// @dev Usage of this function makes sure that any ERC4626 overrides are still good.
    function _toShares(uint256 assets_) internal view returns (uint256) {
        return (assets_ * 1e18) / assetUnit;
    }

    /// @dev Usage of this function makes sure that any ERC4626 overrides are still good.
    function _toAssets(uint256 shares_) internal view returns (uint256) {
        return (shares_ * assetUnit) / 1e18;
    }
}
