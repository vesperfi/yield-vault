// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {YieldVault} from "src/YieldVault.sol";
import {YieldVaultTestBase} from "test/YieldVaultTestBase.t.sol";

/// Tests for Maintainer role
contract YieldVault_Maintainer_Test is YieldVaultTestBase {
    function test_updateDebtRatio() public {
        vault.addStrategy(strategy, debtRatio);
        assertEq(vault.getStrategyConfig(strategy).debtRatio, debtRatio);

        uint256 _newDebtRatio = 5_000;
        vault.updateDebtRatio(strategy, _newDebtRatio);
        assertEq(vault.getStrategyConfig(strategy).debtRatio, _newDebtRatio);
    }

    function test_updateDebtRatio_revertWhen_callerItNotMaintainer() public {
        vm.expectRevert(YieldVault.CallerIsNotMaintainer.selector);
        vm.prank(alice);
        vault.updateDebtRatio(strategy, 4_000);
    }

    function test_updateDebtRatio_revertWhen_debtRatioIsInvalid() public {
        vault.addStrategy(strategy, debtRatio);

        vm.expectRevert(YieldVault.InvalidDebtRatio.selector);
        vault.updateDebtRatio(strategy, 11_000);
    }

    function test_updateDebtRatio_revertWhen_strategyIsNotActive() public {
        vm.expectRevert(YieldVault.StrategyIsNotActive.selector);
        vault.updateDebtRatio(strategy, 5_000);
    }

    function test_updateWithdrawQueue() public {
        vault.addStrategy(strategy, debtRatio);
        vault.addStrategy(strategy2, debtRatio2);
        address[] memory _withdrawQueue = vault.getWithdrawQueue();
        assertEq(_withdrawQueue.length, 2);
        assertEq(_withdrawQueue[0], strategy);
        assertEq(_withdrawQueue[1], strategy2);

        address[] memory _newWithdrawQueue = new address[](2);
        _newWithdrawQueue[0] = strategy2;
        _newWithdrawQueue[1] = strategy;
        vault.updateWithdrawQueue(_newWithdrawQueue);
        address[] memory _withdrawQueueAfter = vault.getWithdrawQueue();
        assertEq(_withdrawQueueAfter.length, 2);
        assertEq(_withdrawQueueAfter, _newWithdrawQueue);
    }

    function test_updateWithdrawQueue_revertWhen_arrayLengthMismatch() public {
        vault.addStrategy(strategy, debtRatio);
        vault.addStrategy(strategy2, debtRatio2);
        assertEq(vault.getWithdrawQueue().length, 2);

        vm.expectRevert(YieldVault.ArrayLengthMismatch.selector);
        address[] memory _newWithdrawQueue = new address[](1);
        _newWithdrawQueue[0] = strategy2;
        vault.updateWithdrawQueue(_newWithdrawQueue);
    }

    function test_updateWithdrawQueue_revertWhen_callerItNotMaintainer() public {
        address[] memory _newWithdrawQueue = new address[](1);
        _newWithdrawQueue[0] = strategy;
        vm.expectRevert(YieldVault.CallerIsNotMaintainer.selector);
        vm.prank(alice);
        vault.updateWithdrawQueue(_newWithdrawQueue);
    }

    function test_updateWithdrawQueue_revertWhen_strategyIsNotActive() public {
        vault.addStrategy(strategy, debtRatio);
        vault.addStrategy(strategy2, debtRatio2);
        assertEq(vault.getWithdrawQueue().length, 2);

        vm.expectRevert(YieldVault.StrategyIsNotActive.selector);
        address _newStrategy = address(0x3);
        address[] memory _newWithdrawQueue = new address[](2);
        _newWithdrawQueue[0] = strategy2;
        _newWithdrawQueue[1] = _newStrategy;
        vault.updateWithdrawQueue(_newWithdrawQueue);
    }

    function test_updateWithdrawQueue_revertWhen_duplicateStrategy() public {
        vault.addStrategy(strategy, debtRatio);
        vault.addStrategy(strategy2, debtRatio2);
        assertEq(vault.getWithdrawQueue().length, 2);

        vm.expectRevert(YieldVault.DuplicateStrategyInQueue.selector);
        address[] memory _newWithdrawQueue = new address[](2);
        _newWithdrawQueue[0] = strategy;
        _newWithdrawQueue[1] = strategy; // Duplicate strategy
        vault.updateWithdrawQueue(_newWithdrawQueue);
    }
}
