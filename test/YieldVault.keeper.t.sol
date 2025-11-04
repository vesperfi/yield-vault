// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ShutdownableUpgradeable as Shutdownable} from "src/ShutdownableUpgradeable.sol";
import {YieldVault} from "src/YieldVault.sol";
import {YieldVaultTestBase} from "test/YieldVaultTestBase.t.sol";

/// Tests for Keeper role
contract YieldVault_Keeper_Test is YieldVaultTestBase {
    function test_pause() public {
        assertFalse(vault.paused());
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_pause_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));

        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.pause();
    }

    function test_unpause() public {
        vault.pause();
        assertTrue(vault.paused());
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_unpause_revertWhen_vaultIsNotPaused() public {
        assertFalse(vault.paused());
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vault.unpause();
    }

    function test_unpause_revertWhen_vaultIsShutdown() public {
        vault.shutdown();
        assertTrue(vault.isShutdown());
        vm.expectRevert(Shutdownable.EnforcedShutdown.selector);
        vault.unpause();
    }

    function test_unpause_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.unpause();
    }

    function test_shutdown() public {
        assertFalse(vault.isShutdown());
        vault.shutdown();
        assertTrue(vault.isShutdown());
    }

    function test_shutdown_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));

        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.shutdown();
    }

    function test_restart() public {
        vault.shutdown();
        assertTrue(vault.isShutdown());
        vault.restart();
        assertFalse(vault.isShutdown());
    }

    function test_restart_revertWhen_vaultIsNotShutdown() public {
        assertFalse(vault.isShutdown());
        vm.expectRevert(Shutdownable.ExpectedShutdown.selector);
        vault.restart();
    }

    function test_restart_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.restart();
    }

    function test_addKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vault.addKeeper(alice);
        assertTrue(vault.isKeeper(alice));
    }

    function test_addKeeper_revertWhen_addingSameKeeperAgain() public {
        vault.addKeeper(alice);
        vm.expectRevert(YieldVault.AddInListFailed.selector);
        vault.addKeeper(alice);
    }

    function test_addKeeper_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.addKeeper(alice);
    }

    function test_removeKeeper() public {
        vault.addKeeper(alice);
        vault.removeKeeper(alice);
        assertFalse(vault.isKeeper(alice));
    }

    function test_removeKeeper_revertWhen_removingNonExistingKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.RemoveFromListFailed.selector);
        vault.removeKeeper(alice);
    }

    function test_removeKeeper_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.removeKeeper(alice);
    }

    function test_addMaintainer() public {
        assertFalse(vault.isMaintainer(alice));
        vault.addMaintainer(alice);
        assertTrue(vault.isMaintainer(alice));
    }

    function test_addMaintainer_revertWhen_addingSameMaintainerAgain() public {
        vault.addMaintainer(alice);
        vm.expectRevert(YieldVault.AddInListFailed.selector);
        vault.addMaintainer(alice);
    }

    function test_addMaintainer_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.addMaintainer(alice);
    }

    function test_removeMaintainer() public {
        vault.addMaintainer(alice);
        vault.removeMaintainer(alice);
        assertFalse(vault.isMaintainer(alice));
    }

    function test_removeMaintainer_revertWhen_removingNonExistingMaintainer() public {
        assertFalse(vault.isMaintainer(alice));
        vm.expectRevert(YieldVault.RemoveFromListFailed.selector);
        vault.removeMaintainer(alice);
    }

    function test_removeMaintainer_revertWhen_callerIsNotKeeper() public {
        assertFalse(vault.isKeeper(alice));
        vm.expectRevert(YieldVault.CallerIsNotKeeper.selector);
        vm.prank(alice);
        vault.removeMaintainer(alice);
    }
}
