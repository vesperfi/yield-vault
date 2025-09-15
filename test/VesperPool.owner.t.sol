// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {VesperPool} from "src/VesperPool.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {VesperPoolTestBase} from "test/VesperPoolTestBase.t.sol";

// Tests for owner role
contract VesperPool_Owner_Test is VesperPoolTestBase {
    function test_addStrategy() public {
        assertEq(pool.totalDebtRatio(), 0);
        pool.addStrategy(strategy, debtRatio);

        VesperPool.StrategyConfig memory _config = pool.getStrategyConfig(strategy);
        assertTrue(_config.active);
        assertEq(_config.debtRatio, debtRatio);
        assertEq(_config.lastRebalance, block.timestamp);

        assertEq(pool.totalDebtRatio(), debtRatio);
        assertEq(pool.getStrategies()[0], strategy);
        assertEq(pool.getWithdrawQueue()[0], strategy);
    }

    function test_addStrategy_multiStrategy() public {
        pool.addStrategy(strategy, debtRatio);

        pool.addStrategy(strategy2, debtRatio2);
        assertEq(pool.totalDebtRatio(), debtRatio + debtRatio2);
        assertEq(pool.getStrategies().length, 2);
        assertEq(pool.getWithdrawQueue().length, 2);
    }

    function test_addStrategy_revertWhen_callerIsNotOwner() public {
        assertNotEq(pool.owner(), alice);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.addStrategy(strategy, debtRatio);
    }

    function test_addStrategy_revertWhen_debtRatioIsInvalid() public {
        pool.addStrategy(strategy, debtRatio);
        vm.expectRevert(VesperPool.InvalidDebtRatio.selector);
        // it will revert as totalDebtRatio will be 11_000 which higher than allowed(10_000)
        pool.addStrategy(strategy2, 2_000);
    }

    function test_addStrategy_revertWhen_strategyIsActive() public {
        pool.addStrategy(strategy, debtRatio);
        vm.expectRevert(VesperPool.StrategyIsActive.selector);
        // adding same strategy again
        pool.addStrategy(strategy, debtRatio2);
    }

    function test_addStrategy_revertWhen_strategyIsNull() public {
        vm.expectRevert(VesperPool.AddressIsNull.selector);
        pool.addStrategy(address(0), debtRatio);
    }

    function test_removeStrategy() public {
        pool.addStrategy(strategy, debtRatio);

        pool.removeStrategy(strategy);
        assertFalse(pool.getStrategyConfig(strategy).active);
        assertEq(pool.totalDebtRatio(), 0);
        assertEq(pool.getStrategies().length, 0);
        assertEq(pool.getWithdrawQueue().length, 0);
    }

    function test_removeStrategy_maintainWithdrawQueueOrder() public {
        pool.addStrategy(strategy, debtRatio);
        uint256 _debtRatio2 = 100;
        pool.addStrategy(strategy2, _debtRatio2);
        address _strategy3 = address(0x3);
        uint256 _debtRatio3 = 150;
        pool.addStrategy(_strategy3, _debtRatio3);
        address[] memory _withdrawQueue = pool.getWithdrawQueue();
        assertEq(_withdrawQueue[0], strategy);
        assertEq(_withdrawQueue[1], strategy2);
        assertEq(_withdrawQueue[2], _strategy3);

        // remove strategy at index 1
        pool.removeStrategy(strategy2);

        address[] memory _withdrawQueueAfter = pool.getWithdrawQueue();
        assertEq(_withdrawQueueAfter.length, 2);
        assertEq(_withdrawQueueAfter[0], strategy);
        assertEq(_withdrawQueueAfter[1], _strategy3);
    }

    function test_removeStrategy_revertWhen_callerIsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.removeStrategy(strategy);
    }

    function test_removeStrategy_revertWhen_debtIsNotZero() public {
        deal(address(asset), address(pool), 100 ether);
        pool.addStrategy(strategy, debtRatio);
        assertTrue(pool.getStrategyConfig(strategy).active);
        // call reportEarning to set debt value
        vm.prank(strategy);
        pool.reportEarning(0, 0, 0);

        vm.expectRevert(VesperPool.TotalDebtShouldBeZero.selector);
        pool.removeStrategy(strategy);
    }

    function test_removeStrategy_revertWhen_removingInactiveStrategy() public {
        assertFalse(pool.getStrategyConfig(strategy).active);

        vm.expectRevert(VesperPool.StrategyIsNotActive.selector);
        pool.removeStrategy(strategy);
    }

    function test_sweep() public {
        MockERC20 _tokenToSweep = deployMockERC20("Token to Sweep", "TTS", 18);
        uint256 _amount = 100 ether;
        address _to = address(0x1a);

        deal(address(_tokenToSweep), address(pool), _amount);
        assertEq(_tokenToSweep.balanceOf(address(pool)), _amount);
        assertEq(_tokenToSweep.balanceOf(_to), 0);

        pool.sweep(address(_tokenToSweep), _to);

        assertEq(_tokenToSweep.balanceOf(address(pool)), 0);
        assertEq(_tokenToSweep.balanceOf(_to), _amount);
    }

    function test_sweep_revertWhen_callerItNotOwner() public {
        address _token = address(0x1212);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.sweep(_token, alice);
    }

    function test_sweep_revertWhen_fromTokenIsAsset() public {
        vm.expectRevert(VesperPool.FromTokenCannotBeAsset.selector);
        pool.sweep(address(asset), alice);
    }

    function test_sweep_revertWhen_receiverIsNull() public {
        address _token = address(0x1212);
        vm.expectRevert(VesperPool.AddressIsNull.selector);
        pool.sweep(_token, address(0));
    }

    function test_updateMaximumProfitAsFee() public {
        // default value is 5_000 aka 50%
        assertEq(pool.maxProfitAsFee(), 5_000);
        pool.updateMaximumProfitAsFee(4_000);
        assertEq(pool.maxProfitAsFee(), 4_000);
    }

    function test_updateMaximumProfitAsFee_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.updateMaximumProfitAsFee(4_000);
    }

    function test_updateMaximumProfitAsFee_revertWhen_inputIsHigherThanMaxLimit() public {
        // 10_000 is max allowed
        vm.expectRevert(VesperPool.InputIsHigherThanMaxLimit.selector);
        pool.updateMaximumProfitAsFee(11_000);
    }

    function test_updateMinimumDepositLimit() public {
        // default value is 1 wei
        assertEq(pool.minimumDepositLimit(), 1);
        pool.updateMinimumDepositLimit(1 ether);
        assertEq(pool.minimumDepositLimit(), 1 ether);
    }

    function test_updateMinimumDepositLimit_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.updateMinimumDepositLimit(1 ether);
    }

    function test_updateMinimumDepositLimit_revertWhen_inputIsZero() public {
        vm.expectRevert(VesperPool.MinimumDepositLimitCannotBeZero.selector);
        pool.updateMinimumDepositLimit(0);
    }

    function test_updatePoolRewards() public {
        assertEq(pool.poolRewards(), address(0));
        address _poolRewards = address(0x121);
        pool.updatePoolRewards(_poolRewards);
        assertEq(pool.poolRewards(), _poolRewards);
    }

    function test_updatePoolRewards_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.updatePoolRewards(address(0x121));
    }

    function test_updatePoolRewards_revertWhen_poolRewardsIsNull() public {
        vm.expectRevert(VesperPool.AddressIsNull.selector);
        pool.updatePoolRewards(address(0));
    }

    function test_updateUniversalFee() public {
        // default value is 200 aka 2%
        assertEq(pool.universalFee(), 200);
        pool.updateUniversalFee(300);
        assertEq(pool.universalFee(), 300);
    }

    function test_updateUniversalFee_revertWhen_callerItNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        pool.updateUniversalFee(300);
    }

    function test_updateUniversalFee_revertWhen_inputIsHigherThanMaxLimit() public {
        // 10_000 is max allowed
        vm.expectRevert(VesperPool.InputIsHigherThanMaxLimit.selector);
        pool.updateUniversalFee(11_000);
    }
}
