// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {YieldVault} from "src/YieldVault.sol";

import {YieldVaultTestBase} from "test/YieldVaultTestBase.t.sol";

// Mock implementation for testing upgrades
contract YieldVaultV6_1 is YieldVault {
    string private _newVersion;

    function initializeV6_1(string memory newVersion_) public reinitializer(2) {
        _newVersion = newVersion_;
    }

    function newVersion() public view returns (string memory) {
        return _newVersion;
    }
}

// Mock implementation with different owner for testing owner mismatch
contract YieldVaultV6_1_WithNewOwner is YieldVault {
    function initializeV6_1(address newOwner_) public reinitializer(2) {
        // This will set a different owner, causing the upgrade to fail
        // Use _transferOwnership to directly change ownership (bypassing 2-step process)
        _transferOwnership(newOwner_);
    }
}

// Tests for proxy upgrade functionality
contract YieldVault_Proxy_Test is YieldVaultTestBase {
    ERC1967Proxy proxy;
    YieldVault proxyVault;

    function setUpProxy() internal {
        // Deploy the implementation
        YieldVault implementation = new YieldVault();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            YieldVault.initialize.selector,
            "Yield Vault",
            "yieldVault",
            address(asset),
            address(this)
        );

        // Deploy the proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        proxyVault = YieldVault(address(proxy));
    }

    function test_upgradeToAndCall() public {
        setUpProxy();

        address currentOwner = proxyVault.owner();
        assertEq(currentOwner, address(this));

        string memory newVersion = "6.1.0";
        YieldVaultV6_1 newImplementation = new YieldVaultV6_1();
        bytes memory initData = abi.encodeWithSelector(YieldVaultV6_1.initializeV6_1.selector, newVersion);

        // Perform the upgrade through the proxy
        proxyVault.upgradeToAndCall(address(newImplementation), initData);

        YieldVaultV6_1 upgradedVault = YieldVaultV6_1(address(proxyVault));
        assertEq(upgradedVault.newVersion(), newVersion);
        assertEq(upgradedVault.owner(), currentOwner);
        assertEq(upgradedVault.asset(), address(asset));
    }

    function test_upgradeToAndCall_revertWhen_ownerMismatch() public {
        setUpProxy();

        address currentOwner = proxyVault.owner();
        assertEq(currentOwner, address(this));

        address fakeOwner = makeAddr("fakeOwner");
        // Deploy the new implementation that changes the owner
        YieldVaultV6_1_WithNewOwner newImplementation = new YieldVaultV6_1_WithNewOwner();
        bytes memory initData = abi.encodeWithSelector(YieldVaultV6_1_WithNewOwner.initializeV6_1.selector, fakeOwner);

        vm.expectRevert(abi.encodeWithSelector(YieldVault.OwnerMismatch.selector, fakeOwner, currentOwner));
        proxyVault.upgradeToAndCall(address(newImplementation), initData);
    }

    function test_upgradeToAndCall_revertWhen_callerIsNotOwner() public {
        setUpProxy();

        YieldVaultV6_1 newImplementation = new YieldVaultV6_1();
        bytes memory initData = abi.encodeWithSelector(YieldVaultV6_1.initializeV6_1.selector, 0);

        // when alice try to upgrade
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        proxyVault.upgradeToAndCall(address(newImplementation), initData);
    }

    function test_upgradeToAndCall_revertWhen_calledDirectlyOnImplementation() public {
        YieldVaultV6_1 newImplementation = new YieldVaultV6_1();
        bytes memory initData = abi.encodeWithSelector(YieldVaultV6_1.initializeV6_1.selector, 1);

        // Note calling directly on implementation and not through proxy
        vm.expectRevert("UUPSUnauthorizedCallContext()");
        vault.upgradeToAndCall(address(newImplementation), initData);
    }
}
