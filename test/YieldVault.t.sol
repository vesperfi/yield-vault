// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IVaultRewards} from "src/interfaces/IVaultRewards.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {ShutdownableUpgradeable as Shutdownable} from "src/ShutdownableUpgradeable.sol";
import {YieldVault} from "src/YieldVault.sol";

import {YieldVaultTestBase} from "test/YieldVaultTestBase.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract YieldVault_Test is YieldVaultTestBase {
    address bob = makeAddr("bob");

    // This is mock function and will be called in strategy context
    function withdraw(uint256 assets_) public {
        YieldVault _vault = YieldVault(msg.sender);
        address _strategy = address(this);
        MockERC20 _asset = MockERC20(_vault.asset());
        // deal assets amount at strategy address
        deal(address(_asset), _strategy, assets_);
        // transfer assets to vault
        require(_asset.transfer(address(_vault), assets_));
    }

    function _deposit(YieldVault vault_, address user_, uint256 assets_) internal {
        deal(vault_.asset(), user_, assets_);
        vm.startPrank(user_);
        MockERC20(vault_.asset()).approve(address(vault_), assets_);
        vault_.deposit(assets_, user_);
        vm.stopPrank();
    }

    function test_deposit() public {
        uint256 _assets = 100 * assetUnit;
        deal(address(asset), alice, _assets);
        vm.startPrank(alice);
        asset.approve(address(vault), _assets);
        vault.deposit(_assets, alice);
        vm.stopPrank();

        assertEq(vault.totalAssets(), _assets);
        assertEq(asset.balanceOf(address(vault)), _assets);
        assertEq(vault.pricePerShare(), assetUnit);
        assertEq(vault.balanceOf(alice), _toShares(_assets));
    }

    function test_deposit_revertWhen_assetsAreLessThanMinimumLimit() public {
        vm.expectRevert(YieldVault.AmountIsBelowDepositLimit.selector);
        vault.deposit(0, alice);
    }

    function test_deposit_revertWhen_vaultIsPaused() public {
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.deposit(10 * assetUnit, alice);
    }

    function test_deposit_revertWhen_vaultIsShutdown() public {
        vault.shutdown();
        vm.expectRevert(Shutdownable.EnforcedShutdown.selector);
        vault.deposit(10 * assetUnit, alice);
    }

    function test_deposit_updateRewards() public {
        address _VaultRewards = makeAddr("VaultRewards");
        vault.updateVaultRewards(_VaultRewards);
        vm.mockCall(_VaultRewards, abi.encodeWithSelector(IVaultRewards.updateReward.selector), "");

        // expect updateRewards to called 1 time for deposit/mint
        vm.expectCall(_VaultRewards, abi.encodeWithSelector(IVaultRewards.updateReward.selector), 1);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        assertEq(vault.balanceOf(alice), _toShares(_assets));
    }

    function test_mint() public {
        uint256 _shares = 100 ether;
        deal(address(asset), alice, _shares);
        vm.startPrank(alice);
        asset.approve(address(vault), _shares);
        vault.mint(_shares, alice);
        vm.stopPrank();
        uint256 _assets = _toAssets(_shares);
        assertEq(vault.totalAssets(), _assets);
        assertEq(asset.balanceOf(address(vault)), _assets);
        assertEq(vault.pricePerShare(), assetUnit);
        assertEq(vault.balanceOf(alice), _shares);
    }

    function test_mint_revertWhen_assetsAreLessThanMinimumLimit() public {
        vm.expectRevert(YieldVault.AmountIsBelowDepositLimit.selector);
        vault.mint(0, alice);
    }

    function test_mint_revertWhen_vaultIsPaused() public {
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.mint(1 ether, alice);
    }

    function test_mint_revertWhen_vaultIsShutdown() public {
        vault.shutdown();
        vm.expectRevert(Shutdownable.EnforcedShutdown.selector);
        vault.mint(1 ether, alice);
    }

    function test_redeem_success() public {
        uint256 _assets = 50 * assetUnit;
        _deposit(vault, alice, _assets);
        assertEq(vault.balanceOf(alice), (_assets * 1e18) / assetUnit);
        assertEq(asset.balanceOf(bob), 0);

        vm.prank(alice);
        vault.redeem(_toShares(_assets), bob, alice);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), _assets);
    }

    function test_redeem_revertWhen_assetsCanNotBeWithdrawn() public {
        vault.addStrategy(strategy, debtRatio);
        _deposit(vault, alice, 100 * assetUnit);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0);

        uint256 _sharesToRedeem = vault.balanceOf(alice);
        // mock strategy.withdraw() call to do nothing
        vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.withdraw.selector), "");
        // expect revert. only 10 assetUnit available to withdraw
        vm.expectRevert(abi.encodeWithSelector(YieldVault.AssetsCanNotBeWithdrawn.selector, 10 * assetUnit));
        vm.prank(alice);
        vault.redeem(_sharesToRedeem, alice, alice);
    }

    function test_redeem_revertWhen_vaultIsShutdown() public {
        vault.shutdown();
        vm.expectRevert(Shutdownable.EnforcedShutdown.selector);
        vault.redeem(1 ether, bob, alice);
    }

    function test_redeem_revertWhen_sharesAreZero() public {
        vm.expectRevert(YieldVault.ZeroShares.selector);
        vault.redeem(0, bob, alice);
    }

    function test_redeem_withdrawFromStrategy() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0);

        // Add this contracts code at strategy address so that withdraw() of this contract can be called in strategy context.
        vm.etch(strategy, address(this).code);

        assertEq(asset.balanceOf(alice), 0);
        uint256 _sharesToRedeem = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(_sharesToRedeem, alice, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(asset.balanceOf(alice), _assets);
    }

    function test_redeem_withdrawFromSecondStrategy() public {
        // no fund in firstStrategy
        address _firstStrategy = makeAddr("_firstStrategy");
        vault.addStrategy(_firstStrategy, 100);
        vault.addStrategy(strategy, debtRatio);

        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy

        // Add this contracts code at strategy address so that withdraw() of this contract can be called in strategy context.
        vm.etch(strategy, address(this).code);

        assertEq(asset.balanceOf(alice), 0);
        uint256 _sharesToRedeem = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(_sharesToRedeem, alice, alice);

        assertEq(asset.balanceOf(alice), _assets);
    }

    function test_redeem_withdrawFromMultipleStrategy() public {
        vault.addStrategy(strategy, 5_000);
        vault.addStrategy(strategy2, 4_000);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy

        vm.prank(strategy2);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy2

        assertEq(asset.balanceOf(alice), 0);
        assertGt(vault.getStrategyConfig(strategy).totalDebt, 0);
        assertGt(vault.getStrategyConfig(strategy2).totalDebt, 0);

        // Add this contracts code at strategy address so that withdraw() of this contract can be called in strategy context.
        vm.etch(strategy, address(this).code);
        vm.etch(strategy2, address(this).code);
        uint256 _sharesToRedeem = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(_sharesToRedeem, alice, alice);

        assertEq(asset.balanceOf(alice), _assets);
        assertEq(vault.getStrategyConfig(strategy).totalDebt, 0);
        assertEq(vault.getStrategyConfig(strategy2).totalDebt, 0);
    }

    function test_redeem_withdrawFromStrategy_errorInTryCatch() public {
        vault.addStrategy(strategy, debtRatio);
        vault.addStrategy(strategy2, debtRatio2);
        _deposit(vault, alice, 100 * assetUnit);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy

        vm.prank(strategy2);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy2

        assertEq(asset.balanceOf(alice), 0);
        uint256 _debtOfStrategy1 = vault.getStrategyConfig(strategy).totalDebt;
        uint256 _debtOfStrategy2 = vault.getStrategyConfig(strategy2).totalDebt;

        // revert withdraw() for 1st strategy
        vm.mockCallRevert(strategy, abi.encodeWithSelector(IStrategy.withdraw.selector), "");
        // Add this contracts code at strategy address so that withdraw() of this contract can be called in strategy context.
        vm.etch(strategy2, address(this).code);
        vm.prank(alice);
        // Total debtRatio of strategies is 10_000, so any withdraw/redeem will call withdraw on strategy
        uint256 _sharesToRedeem = 1 ether; // pps is 1:1
        vault.redeem(_sharesToRedeem, alice, alice);

        uint256 _assets = _toAssets(_sharesToRedeem);
        assertEq(asset.balanceOf(alice), _assets);
        assertEq(vault.getStrategyConfig(strategy).totalDebt, _debtOfStrategy1);
        assertEq(vault.getStrategyConfig(strategy2).totalDebt, _debtOfStrategy2 - _assets);
    }

    function test_withdraw() public {
        uint256 _assets = 50 * assetUnit;
        _deposit(vault, alice, _assets);
        assertEq(vault.balanceOf(alice), (_assets * 1e18) / assetUnit);
        assertEq(asset.balanceOf(bob), 0);

        vm.prank(alice);
        vault.withdraw(_assets, bob, alice);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(asset.balanceOf(bob), _assets);
    }

    function test_withdraw_revertWhen_assetsAreZero() public {
        vm.expectRevert(YieldVault.ZeroAssets.selector);
        vault.withdraw(0, bob, alice);
    }

    function test_withdraw_revertWhen_vaultIsShutdown() public {
        vault.shutdown();
        vm.expectRevert(Shutdownable.EnforcedShutdown.selector);
        vault.withdraw(1 * assetUnit, bob, alice);
    }

    function test_withdraw_updateRewards() public {
        address _VaultRewards = makeAddr("VaultRewards");
        vault.updateVaultRewards(_VaultRewards);
        vm.mockCall(_VaultRewards, abi.encodeWithSelector(IVaultRewards.updateReward.selector), "");

        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);

        // expect updateRewards to called 1 time for withdraw/redeem
        vm.expectCall(_VaultRewards, abi.encodeWithSelector(IVaultRewards.updateReward.selector), 1);
        vm.prank(alice);
        vault.withdraw(_assets, bob, alice);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_transfer_updateRewards() public {
        address _VaultRewards = makeAddr("VaultRewards");
        vault.updateVaultRewards(_VaultRewards);
        vm.mockCall(_VaultRewards, abi.encodeWithSelector(IVaultRewards.updateReward.selector), "");

        _deposit(vault, alice, 100 * assetUnit);

        // expect updateRewards to called 2 times for transfer()
        vm.expectCall(_VaultRewards, abi.encodeWithSelector(IVaultRewards.updateReward.selector), 2);
        uint256 _sharesToTransfer = vault.balanceOf(alice);
        vm.prank(alice);
        require(vault.transfer(bob, _sharesToTransfer));
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), _sharesToTransfer);
    }
}
