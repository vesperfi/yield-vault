// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {YieldVault} from "src/YieldVault.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

import {YieldVaultTestBase} from "test/YieldVaultTestBase.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants} from "test/helpers/Constants.sol";

contract YieldVault_Strategy_Test is YieldVaultTestBase {
    function _deposit(YieldVault vault_, address user_, uint256 assets_) internal {
        deal(vault_.asset(), user_, assets_);
        vm.startPrank(user_);
        MockERC20(vault_.asset()).approve(address(vault_), assets_);
        vault_.deposit(assets_, user_);
        vm.stopPrank();
    }

    function _calculateFee(YieldVault vault_, uint256 profit_) internal view returns (uint256 _fee) {
        uint256 _performanceFee = vault_.performanceFee();
        if (_performanceFee > 0) {
            _fee = (profit_ * _performanceFee) / Constants.MAX_BPS;
        }
    }

    function test_reportEarning() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        assertEq(vault.totalAssets(), _assets);

        assertEq(vault.getStrategyConfig(strategy).totalDebt, 0);

        vm.prank(strategy);
        vault.reportEarning(0, 0, 0);

        uint256 _expectedTotalDebt = (_assets * debtRatio) / Constants.MAX_BPS;
        assertEq(vault.totalDebt(), _expectedTotalDebt);
        assertEq(vault.getStrategyConfig(strategy).totalDebt, _expectedTotalDebt);
        assertEq(vault.totalDebtRatio(), debtRatio);
    }

    function test_reportEarning_vaultIsShutdown() public {
        vault.addStrategy(strategy, debtRatio);
        _deposit(vault, alice, 100 * assetUnit);

        assertEq(vault.getStrategyConfig(strategy).totalDebt, 0);
        vault.shutdown();

        vm.prank(strategy);
        vault.reportEarning(0, 0, 0);

        assertEq(vault.totalDebt(), 0);
        assertEq(vault.getStrategyConfig(strategy).totalDebt, 0);
    }

    function test_reportEarning_loss() public {
        vault.addStrategy(strategy, debtRatio);
        _deposit(vault, alice, 100 * assetUnit);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy

        YieldVault.StrategyConfig memory _configBefore = vault.getStrategyConfig(strategy);
        uint256 _totalDebtBefore = vault.totalDebt();
        uint256 _totalDebtRatioBefore = vault.totalDebtRatio();

        // report loss
        uint256 _lossAmount = 5 * assetUnit;
        vm.prank(strategy);
        vault.reportEarning(0, _lossAmount, 0);

        YieldVault.StrategyConfig memory _configAfter = vault.getStrategyConfig(strategy);
        assertEq(_configAfter.totalLoss, _lossAmount);
        assertEq(_configAfter.totalDebt, _configBefore.totalDebt - _lossAmount);
        assertEq(vault.totalDebt(), _totalDebtBefore - _lossAmount);

        uint256 _changeInDebtRatio = (_lossAmount * Constants.MAX_BPS) / vault.totalAssets();
        assertEq(_configAfter.debtRatio, _configBefore.debtRatio - _changeInDebtRatio);
        assertEq(vault.totalDebtRatio(), _totalDebtRatioBefore - _changeInDebtRatio);
    }

    function test_reportEarning_payback() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy
        // decrease debt ratio for payback
        uint256 _newDebtRatio = debtRatio - 1_000;
        vault.updateDebtRatio(strategy, _newDebtRatio);

        // report payback
        vm.startPrank(strategy);
        uint256 _paybackAmount = vault.excessDebt(strategy);
        asset.approve(address(vault), _paybackAmount);
        vault.reportEarning(0, 0, _paybackAmount);
        vm.stopPrank();

        uint256 _expectedDebt = (_assets * _newDebtRatio) / Constants.MAX_BPS;
        YieldVault.StrategyConfig memory _config = vault.getStrategyConfig(strategy);
        assertEq(_config.totalDebt, _expectedDebt);
        assertEq(vault.totalDebt(), _expectedDebt);
        assertEq(_config.debtRatio, _newDebtRatio);
        assertEq(vault.totalDebtRatio(), _newDebtRatio);
    }

    function test_reportEarning_profit() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy
        uint256 _ppsBefore = vault.pricePerShare();

        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        asset.approve(address(vault), _profitAmount);
        vault.reportEarning(_profitAmount, 0, 0);
        vm.stopPrank();

        assertEq(vault.getStrategyConfig(strategy).totalProfit, _profitAmount);
        assertGt(vault.pricePerShare(), _ppsBefore);
    }

    function test_reportEarning_profitAndPayback() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy
        // decrease debt ratio for payback
        uint256 _newDebtRatio = debtRatio - 1_000;
        vault.updateDebtRatio(strategy, _newDebtRatio);
        uint256 _ppsBefore = vault.pricePerShare();

        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        uint256 _paybackAmount = vault.excessDebt(strategy);
        asset.approve(address(vault), _profitAmount + _paybackAmount);
        vault.reportEarning(_profitAmount, 0, _paybackAmount);
        vm.stopPrank();

        YieldVault.StrategyConfig memory _config = vault.getStrategyConfig(strategy);
        assertEq(_config.totalProfit, _profitAmount);
        assertGt(vault.pricePerShare(), _ppsBefore);
        uint256 _expectedDebt = (_assets * _newDebtRatio) / Constants.MAX_BPS;
        assertEq(_config.totalDebt, _expectedDebt);
    }

    function test_reportEarning_profitAndPayback_revertWithIncorrectPayback() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy
        // decrease debt ratio for rebalance
        uint256 _newDebtRatio = debtRatio - 1_000;
        vault.updateDebtRatio(strategy, _newDebtRatio);

        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        // report payback less than excessDebt
        uint256 _payback = vault.excessDebt(strategy) - 1;
        asset.approve(address(vault), _profitAmount + _payback);
        vm.expectRevert(abi.encodeWithSelector(YieldVault.IncorrectPayback.selector, _payback, _payback + 1));
        vault.reportEarning(_profitAmount, 0, _payback);
        vm.stopPrank();
    }

    function test_reportEarning_profitWithPerformanceFee() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(vault, alice, _assets);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy
        assertEq(vault.balanceOf(feeCollector), 0);
        vm.warp(block.timestamp + 1 days); // time travel to earn some fee
        uint256 _ppsBefore = vault.pricePerShare();

        // Set performance fee
        vault.updatePerformanceFee(200); // 2%
        // mock call to return feeCollector
        vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.feeCollector.selector), abi.encode(feeCollector));
        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        uint256 _expectedFee = _calculateFee(vault, _profitAmount);
        asset.approve(address(vault), _profitAmount);
        vault.reportEarning(_profitAmount, 0, 0);
        vm.stopPrank();

        assertEq(vault.getStrategyConfig(strategy).totalProfit, _profitAmount);
        assertGt(vault.pricePerShare(), _ppsBefore);
        assertEq(vault.balanceOf(feeCollector), _toShares(_expectedFee));
    }

    function test_reportEarning_revertWhen_strategyIsNotActive() public {
        vault.addStrategy(strategy, debtRatio);

        vm.expectRevert(YieldVault.StrategyIsNotActive.selector);
        vm.prank(alice);
        vault.reportEarning(0, 0, 0);
    }

    function test_reportEarning_revertWhen_strategyHasLessFundThanReporting() public {
        vault.addStrategy(strategy, debtRatio);
        _deposit(vault, alice, 100 * assetUnit);
        vm.startPrank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy

        // report payback
        uint256 _paybackAmount = 110 * assetUnit;
        asset.approve(address(vault), _paybackAmount);
        vm.expectRevert(YieldVault.InsufficientBalance.selector);
        vault.reportEarning(0, 0, _paybackAmount);
        vm.stopPrank();
    }

    function test_reportLoss() public {
        vault.addStrategy(strategy, debtRatio);
        _deposit(vault, alice, 100 * assetUnit);
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0); // deploy fund in strategy

        YieldVault.StrategyConfig memory _configBefore = vault.getStrategyConfig(strategy);
        uint256 _totalDebtBefore = vault.totalDebt();
        uint256 _totalDebtRatioBefore = vault.totalDebtRatio();

        // report loss
        uint256 _lossAmount = 5 * assetUnit;
        vm.prank(strategy);
        vault.reportLoss(_lossAmount);

        YieldVault.StrategyConfig memory _configAfter = vault.getStrategyConfig(strategy);
        assertEq(_configAfter.totalLoss, _lossAmount);
        assertEq(_configAfter.totalDebt, _configBefore.totalDebt - _lossAmount);
        assertEq(vault.totalDebt(), _totalDebtBefore - _lossAmount);

        uint256 _changeInDebtRatio = (_lossAmount * Constants.MAX_BPS) / vault.totalAssets();
        assertEq(_configAfter.debtRatio, _configBefore.debtRatio - _changeInDebtRatio);
        assertEq(vault.totalDebtRatio(), _totalDebtRatioBefore - _changeInDebtRatio);
    }

    function test_reportLoss_zeroAmount() public {
        vault.addStrategy(strategy, debtRatio);
        YieldVault.StrategyConfig memory _configBefore = vault.getStrategyConfig(strategy);

        vm.prank(strategy);
        vault.reportLoss(0);

        YieldVault.StrategyConfig memory _configAfter = vault.getStrategyConfig(strategy);
        assertEq(_configAfter.totalLoss, 0);
        assertEq(_configAfter.totalDebt, _configBefore.totalDebt);
    }

    function test_reportLoss_revertWhen_lossIsHigherThanDebt() public {
        vault.addStrategy(strategy, debtRatio);
        vm.expectRevert(YieldVault.LossTooHigh.selector);
        vm.prank(strategy);
        vault.reportLoss(1 ether);
    }

    function test_reportLoss_revertWhen_strategyIsNotActive() public {
        vm.expectRevert(YieldVault.StrategyIsNotActive.selector);
        vm.prank(strategy);
        vault.reportLoss(1 ether);
    }
}
