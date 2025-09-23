// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {VesperPool} from "src/VesperPool.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";

import {VesperPoolTestBase} from "test/VesperPoolTestBase.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants} from "test/helpers/Constants.sol";

contract VesperPool_Strategy_Test is VesperPoolTestBase {
    function _deposit(VesperPool pool_, address user_, uint256 assets_) internal {
        deal(pool_.asset(), user_, assets_);
        vm.startPrank(user_);
        MockERC20(pool_.asset()).approve(address(pool_), assets_);
        pool_.deposit(assets_, user_);
        vm.stopPrank();
    }

    function _calculateFee(VesperPool pool_, address strategy_) internal view returns (uint256 _fee) {
        VesperPool.StrategyConfig memory _config = pool_.getStrategyConfig(strategy_);
        _fee =
            (pool_.universalFee() * (block.timestamp - _config.lastRebalance) * _config.totalDebt) /
            (Constants.MAX_BPS * Constants.ONE_YEAR);
    }

    function test_reportEarning() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(pool, alice, _assets);
        assertEq(pool.totalAssets(), _assets);

        assertEq(pool.getStrategyConfig(strategy).totalDebt, 0);

        vm.prank(strategy);
        pool.reportEarning(0, 0, 0);

        uint256 _expectedTotalDebt = (_assets * debtRatio) / Constants.MAX_BPS;
        assertEq(pool.totalDebt(), _expectedTotalDebt);
        assertEq(pool.getStrategyConfig(strategy).totalDebt, _expectedTotalDebt);
        assertEq(pool.totalDebtRatio(), debtRatio);
    }

    function test_reportEarning_poolIsShutdown() public {
        pool.addStrategy(strategy, debtRatio);
        _deposit(pool, alice, 100 * assetUnit);

        assertEq(pool.getStrategyConfig(strategy).totalDebt, 0);
        pool.shutdown();

        vm.prank(strategy);
        pool.reportEarning(0, 0, 0);

        assertEq(pool.totalDebt(), 0);
        assertEq(pool.getStrategyConfig(strategy).totalDebt, 0);
    }

    function test_reportEarning_loss() public {
        pool.addStrategy(strategy, debtRatio);
        _deposit(pool, alice, 100 * assetUnit);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy

        VesperPool.StrategyConfig memory _configBefore = pool.getStrategyConfig(strategy);
        uint256 _totalDebtBefore = pool.totalDebt();
        uint256 _totalDebtRatioBefore = pool.totalDebtRatio();

        // report loss
        uint256 _lossAmount = 5 * assetUnit;
        vm.prank(strategy);
        pool.reportEarning(0, _lossAmount, 0);

        VesperPool.StrategyConfig memory _configAfter = pool.getStrategyConfig(strategy);
        assertEq(_configAfter.totalLoss, _lossAmount);
        assertEq(_configAfter.totalDebt, _configBefore.totalDebt - _lossAmount);
        assertEq(pool.totalDebt(), _totalDebtBefore - _lossAmount);

        uint256 _changeInDebtRatio = (_lossAmount * Constants.MAX_BPS) / pool.totalAssets();
        assertEq(_configAfter.debtRatio, _configBefore.debtRatio - _changeInDebtRatio);
        assertEq(pool.totalDebtRatio(), _totalDebtRatioBefore - _changeInDebtRatio);
    }

    function test_reportEarning_payback() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(pool, alice, _assets);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy
        // decrease debt ratio for payback
        uint256 _newDebtRatio = debtRatio - 1_000;
        pool.updateDebtRatio(strategy, _newDebtRatio);

        // report payback
        vm.startPrank(strategy);
        uint256 _paybackAmount = pool.excessDebt(strategy);
        asset.approve(address(pool), _paybackAmount);
        pool.reportEarning(0, 0, _paybackAmount);
        vm.stopPrank();

        uint256 _expectedDebt = (_assets * _newDebtRatio) / Constants.MAX_BPS;
        VesperPool.StrategyConfig memory _config = pool.getStrategyConfig(strategy);
        assertEq(_config.totalDebt, _expectedDebt);
        assertEq(pool.totalDebt(), _expectedDebt);
        assertEq(_config.debtRatio, _newDebtRatio);
        assertEq(pool.totalDebtRatio(), _newDebtRatio);
    }

    function test_reportEarning_profit() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(pool, alice, _assets);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy
        uint256 _ppsBefore = pool.pricePerShare();

        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        asset.approve(address(pool), _profitAmount);
        pool.reportEarning(_profitAmount, 0, 0);
        vm.stopPrank();

        assertEq(pool.getStrategyConfig(strategy).totalProfit, _profitAmount);
        assertGt(pool.pricePerShare(), _ppsBefore);
    }

    function test_reportEarning_profitAndPayback() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(pool, alice, _assets);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy
        // decrease debt ratio for payback
        uint256 _newDebtRatio = debtRatio - 1_000;
        pool.updateDebtRatio(strategy, _newDebtRatio);
        uint256 _ppsBefore = pool.pricePerShare();

        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        uint256 _paybackAmount = pool.excessDebt(strategy);
        asset.approve(address(pool), _profitAmount + _paybackAmount);
        pool.reportEarning(_profitAmount, 0, _paybackAmount);
        vm.stopPrank();

        VesperPool.StrategyConfig memory _config = pool.getStrategyConfig(strategy);
        assertEq(_config.totalProfit, _profitAmount);
        assertGt(pool.pricePerShare(), _ppsBefore);
        uint256 _expectedDebt = (_assets * _newDebtRatio) / Constants.MAX_BPS;
        assertEq(_config.totalDebt, _expectedDebt);
    }

    function test_reportEarning_profitWithUniversalFee() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(pool, alice, _assets);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy
        assertEq(pool.balanceOf(feeCollector), 0);
        vm.warp(block.timestamp + 1 days); // time travel to earn some fee
        uint256 _ppsBefore = pool.pricePerShare();

        // mock call to return feeCollector
        vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.feeCollector.selector), abi.encode(feeCollector));
        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = 5 * assetUnit;
        uint256 _expectedFee = _calculateFee(pool, strategy);
        asset.approve(address(pool), _profitAmount);
        pool.reportEarning(_profitAmount, 0, 0);
        vm.stopPrank();

        assertEq(pool.getStrategyConfig(strategy).totalProfit, _profitAmount);
        assertGt(pool.pricePerShare(), _ppsBefore);
        assertEq(pool.balanceOf(feeCollector), _toShares(_expectedFee));
    }

    function test_reportEarning_profitWithUniversalFee2() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _assets = 100 * assetUnit;
        _deposit(pool, alice, _assets);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy
        vm.warp(block.timestamp + 1 days); // time travel to earn some fee

        // mock call to return feeCollector
        vm.mockCall(strategy, abi.encodeWithSelector(IStrategy.feeCollector.selector), abi.encode(feeCollector));
        // report payback
        vm.startPrank(strategy);
        uint256 _profitAmount = (5 * assetUnit) / 1000; // very less amount as profit
        // 0.005 assetUnit as profit will lead fee being more than pool.maxProfitAsFee() percentage of profit
        // and in this case fee will be calculated as given below.
        uint256 _expectedFee = (_profitAmount * pool.maxProfitAsFee()) / Constants.MAX_BPS;
        asset.approve(address(pool), _profitAmount);
        pool.reportEarning(_profitAmount, 0, 0);
        vm.stopPrank();

        assertEq(pool.balanceOf(feeCollector), _toShares(_expectedFee));
    }

    function test_reportEarning_revertWhen_strategyIsNotActive() public {
        pool.addStrategy(strategy, debtRatio);

        vm.expectRevert(VesperPool.StrategyIsNotActive.selector);
        vm.prank(alice);
        pool.reportEarning(0, 0, 0);
    }

    function test_reportEarning_revertWhen_strategyHasLessFundThanReporting() public {
        pool.addStrategy(strategy, debtRatio);
        _deposit(pool, alice, 100 * assetUnit);
        vm.startPrank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy

        // report payback
        uint256 _paybackAmount = 110 * assetUnit;
        asset.approve(address(pool), _paybackAmount);
        vm.expectRevert(VesperPool.InsufficientBalance.selector);
        pool.reportEarning(0, 0, _paybackAmount);
        vm.stopPrank();
    }

    function test_reportLoss() public {
        pool.addStrategy(strategy, debtRatio);
        _deposit(pool, alice, 100 * assetUnit);
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0); // deploy fund in strategy

        VesperPool.StrategyConfig memory _configBefore = pool.getStrategyConfig(strategy);
        uint256 _totalDebtBefore = pool.totalDebt();
        uint256 _totalDebtRatioBefore = pool.totalDebtRatio();

        // report loss
        uint256 _lossAmount = 5 * assetUnit;
        vm.prank(strategy);
        pool.reportLoss(_lossAmount);

        VesperPool.StrategyConfig memory _configAfter = pool.getStrategyConfig(strategy);
        assertEq(_configAfter.totalLoss, _lossAmount);
        assertEq(_configAfter.totalDebt, _configBefore.totalDebt - _lossAmount);
        assertEq(pool.totalDebt(), _totalDebtBefore - _lossAmount);

        uint256 _changeInDebtRatio = (_lossAmount * Constants.MAX_BPS) / pool.totalAssets();
        assertEq(_configAfter.debtRatio, _configBefore.debtRatio - _changeInDebtRatio);
        assertEq(pool.totalDebtRatio(), _totalDebtRatioBefore - _changeInDebtRatio);
    }

    function test_reportLoss_zeroAmount() public {
        pool.addStrategy(strategy, debtRatio);
        VesperPool.StrategyConfig memory _configBefore = pool.getStrategyConfig(strategy);

        vm.prank(strategy);
        pool.reportLoss(0);

        VesperPool.StrategyConfig memory _configAfter = pool.getStrategyConfig(strategy);
        assertEq(_configAfter.totalLoss, 0);
        assertEq(_configAfter.totalDebt, _configBefore.totalDebt);
    }

    function test_reportLoss_revertWhen_lossIsHigherThanDebt() public {
        pool.addStrategy(strategy, debtRatio);
        vm.expectRevert(VesperPool.LossTooHigh.selector);
        vm.prank(strategy);
        pool.reportLoss(1 ether);
    }

    function test_reportLoss_revertWhen_strategyIsNotActive() public {
        vm.expectRevert(VesperPool.StrategyIsNotActive.selector);
        vm.prank(strategy);
        pool.reportLoss(1 ether);
    }
}
