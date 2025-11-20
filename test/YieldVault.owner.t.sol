// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {YieldVault} from "src/YieldVault.sol";

import {YieldVaultTestBase} from "test/YieldVaultTestBase.t.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

// Tests for owner role
contract YieldVault_Owner_Test is YieldVaultTestBase {
    function test_addStrategy() public {
        assertEq(vault.totalDebtRatio(), 0);
        vault.addStrategy(strategy, debtRatio);

        YieldVault.StrategyConfig memory _config = vault.getStrategyConfig(strategy);
        assertTrue(_config.active);
        assertEq(_config.debtRatio, debtRatio);

        assertEq(vault.totalDebtRatio(), debtRatio);
        assertEq(vault.getStrategies()[0], strategy);
        assertEq(vault.getWithdrawQueue()[0], strategy);
    }

    function test_addStrategy_multiStrategy() public {
        vault.addStrategy(strategy, debtRatio);

        vault.addStrategy(strategy2, debtRatio2);
        assertEq(vault.totalDebtRatio(), debtRatio + debtRatio2);
        assertEq(vault.getStrategies().length, 2);
        assertEq(vault.getWithdrawQueue().length, 2);
    }

    function test_addStrategy_revertWhen_callerIsNotOwner() public {
        assertNotEq(vault.owner(), alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        vault.addStrategy(strategy, debtRatio);
    }

    function test_addStrategy_revertWhen_debtRatioIsInvalid() public {
        vault.addStrategy(strategy, debtRatio);
        vm.expectRevert(YieldVault.InvalidDebtRatio.selector);
        // it will revert as totalDebtRatio will be 11_000 which higher than allowed(10_000)
        vault.addStrategy(strategy2, 2_000);
    }

    function test_addStrategy_revertWhen_strategyIsActive() public {
        vault.addStrategy(strategy, debtRatio);
        vm.expectRevert(YieldVault.StrategyIsActive.selector);
        // adding same strategy again
        vault.addStrategy(strategy, debtRatio2);
    }

    function test_addStrategy_revertWhen_strategyIsNull() public {
        vm.expectRevert(YieldVault.AddressIsNull.selector);
        vault.addStrategy(address(0), debtRatio);
    }

    function test_removeStrategy() public {
        vault.addStrategy(strategy, debtRatio);

        vault.removeStrategy(strategy);
        assertFalse(vault.getStrategyConfig(strategy).active);
        assertEq(vault.totalDebtRatio(), 0);
        assertEq(vault.getStrategies().length, 0);
        assertEq(vault.getWithdrawQueue().length, 0);
    }

    function test_removeStrategy_maintainWithdrawQueueOrder() public {
        vault.addStrategy(strategy, debtRatio);
        uint256 _debtRatio2 = 100;
        vault.addStrategy(strategy2, _debtRatio2);
        address _strategy3 = address(0x3);
        uint256 _debtRatio3 = 150;
        vault.addStrategy(_strategy3, _debtRatio3);
        address[] memory _withdrawQueue = vault.getWithdrawQueue();
        assertEq(_withdrawQueue[0], strategy);
        assertEq(_withdrawQueue[1], strategy2);
        assertEq(_withdrawQueue[2], _strategy3);

        // remove strategy at index 1
        vault.removeStrategy(strategy2);

        address[] memory _withdrawQueueAfter = vault.getWithdrawQueue();
        assertEq(_withdrawQueueAfter.length, 2);
        assertEq(_withdrawQueueAfter[0], strategy);
        assertEq(_withdrawQueueAfter[1], _strategy3);
    }

    function test_removeStrategy_revertWhen_callerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        vault.removeStrategy(strategy);
    }

    function test_removeStrategy_revertWhen_debtIsNotZero() public {
        deal(address(asset), address(vault), 100 ether);
        vault.addStrategy(strategy, debtRatio);
        assertTrue(vault.getStrategyConfig(strategy).active);
        // call reportEarning to set debt value
        vm.prank(strategy);
        vault.reportEarning(0, 0, 0);

        vm.expectRevert(YieldVault.TotalDebtShouldBeZero.selector);
        vault.removeStrategy(strategy);
    }

    function test_removeStrategy_revertWhen_removingInactiveStrategy() public {
        assertFalse(vault.getStrategyConfig(strategy).active);

        vm.expectRevert(YieldVault.StrategyIsNotActive.selector);
        vault.removeStrategy(strategy);
    }

    function test_sweep() public {
        MockERC20 _tokenToSweep = new MockERC20();
        _tokenToSweep.setDecimals(18);
        uint256 _amount = 100 ether;
        address _to = address(0x1a);

        deal(address(_tokenToSweep), address(vault), _amount);
        assertEq(_tokenToSweep.balanceOf(address(vault)), _amount);
        assertEq(_tokenToSweep.balanceOf(_to), 0);

        vault.sweep(address(_tokenToSweep), _to);

        assertEq(_tokenToSweep.balanceOf(address(vault)), 0);
        assertEq(_tokenToSweep.balanceOf(_to), _amount);
    }

    function test_sweep_revertWhen_callerItNotOwner() public {
        address _token = address(0x1212);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        vault.sweep(_token, alice);
    }

    function test_sweep_revertWhen_fromTokenIsAsset() public {
        vm.expectRevert(YieldVault.FromTokenCannotBeAsset.selector);
        vault.sweep(address(asset), alice);
    }

    function test_sweep_revertWhen_receiverIsNull() public {
        address _token = address(0x1212);
        vm.expectRevert(YieldVault.AddressIsNull.selector);
        vault.sweep(_token, address(0));
    }

    function test_updatePerformanceFee() public {
        // default value is 0
        assertEq(vault.performanceFee(), 0);
        vault.updatePerformanceFee(4_000);
        assertEq(vault.performanceFee(), 4_000);
    }

    function test_updatePerformanceFee_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        vault.updatePerformanceFee(4_000);
    }

    function test_updatePerformanceFee_revertWhen_inputIsHigherThanMaxLimit() public {
        // 10_000 is max allowed
        vm.expectRevert(YieldVault.InputIsHigherThanMaxLimit.selector);
        vault.updatePerformanceFee(11_000);
    }

    function test_updateMinimumDepositLimit() public {
        // default value is 1 wei
        assertEq(vault.minimumDepositLimit(), 1);
        vault.updateMinimumDepositLimit(1 ether);
        assertEq(vault.minimumDepositLimit(), 1 ether);
    }

    function test_updateMinimumDepositLimit_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        vault.updateMinimumDepositLimit(1 ether);
    }

    function test_updateMinimumDepositLimit_revertWhen_inputIsZero() public {
        vm.expectRevert(YieldVault.MinimumDepositLimitCannotBeZero.selector);
        vault.updateMinimumDepositLimit(0);
    }

    function test_updateVaultRewards() public {
        assertEq(vault.vaultRewards(), address(0));
        address _VaultRewards = address(0x121);
        vault.updateVaultRewards(_VaultRewards);
        assertEq(vault.vaultRewards(), _VaultRewards);
    }

    function test_updateVaultRewards_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        vault.updateVaultRewards(address(0x121));
    }

    function test_updateVaultRewards_revertWhen_VaultRewardsIsNull() public {
        vm.expectRevert(YieldVault.AddressIsNull.selector);
        vault.updateVaultRewards(address(0));
    }
}
