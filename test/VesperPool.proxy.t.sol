// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {OwnableUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VesperPool} from "src/VesperPool.sol";

import {VesperPoolTestBase} from "test/VesperPoolTestBase.t.sol";

// Mock implementation for testing upgrades
contract VesperPoolV6_1 is VesperPool {
    string private _newVersion;

    function initializeV6_1(string memory newVersion_) public reinitializer(2) {
        _newVersion = newVersion_;
    }

    function newVersion() public view returns (string memory) {
        return _newVersion;
    }
}

// Mock implementation with different owner for testing owner mismatch
contract VesperPoolV6_1_WithNewOwner is VesperPool {
    function initializeV6_1(address newOwner_) public reinitializer(2) {
        // This will set a different owner, causing the upgrade to fail
        // Use _transferOwnership to directly change ownership (bypassing 2-step process)
        _transferOwnership(newOwner_);
    }
}

// Tests for proxy upgrade functionality
contract VesperPool_Proxy_Test is VesperPoolTestBase {
    ERC1967Proxy proxy;
    VesperPool proxyPool;

    function setUpProxy() internal {
        // Deploy the implementation
        VesperPool implementation = new VesperPool();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            VesperPool.initialize.selector,
            "Vesper Pool V6",
            "VesperPoolV6",
            address(asset)
        );

        // Deploy the proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        proxyPool = VesperPool(address(proxy));
    }

    function test_upgradeToAndCall() public {
        setUpProxy();

        address currentOwner = proxyPool.owner();
        assertEq(currentOwner, address(this));

        string memory newVersion = "6.1.0";
        VesperPoolV6_1 newImplementation = new VesperPoolV6_1();
        bytes memory initData = abi.encodeWithSelector(VesperPoolV6_1.initializeV6_1.selector, newVersion);

        // Perform the upgrade through the proxy
        proxyPool.upgradeToAndCall(address(newImplementation), initData);

        VesperPoolV6_1 upgradedPool = VesperPoolV6_1(address(proxyPool));
        assertEq(upgradedPool.newVersion(), newVersion);
        assertEq(upgradedPool.owner(), currentOwner);
        assertEq(upgradedPool.asset(), address(asset));
    }

    function test_upgradeToAndCall_revertWhen_ownerMismatch() public {
        setUpProxy();

        address currentOwner = proxyPool.owner();
        assertEq(currentOwner, address(this));

        address fakeOwner = makeAddr("fakeOwner");
        // Deploy the new implementation that changes the owner
        VesperPoolV6_1_WithNewOwner newImplementation = new VesperPoolV6_1_WithNewOwner();
        bytes memory initData = abi.encodeWithSelector(VesperPoolV6_1_WithNewOwner.initializeV6_1.selector, fakeOwner);

        vm.expectRevert(abi.encodeWithSelector(VesperPool.OwnerMismatch.selector, fakeOwner, currentOwner));
        proxyPool.upgradeToAndCall(address(newImplementation), initData);
    }

    function test_upgradeToAndCall_revertWhen_callerIsNotOwner() public {
        setUpProxy();

        VesperPoolV6_1 newImplementation = new VesperPoolV6_1();
        bytes memory initData = abi.encodeWithSelector(VesperPoolV6_1.initializeV6_1.selector, 0);

        // when alice try to upgrade
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        proxyPool.upgradeToAndCall(address(newImplementation), initData);
    }

    function test_upgradeToAndCall_revertWhen_calledDirectlyOnImplementation() public {
        VesperPoolV6_1 newImplementation = new VesperPoolV6_1();
        bytes memory initData = abi.encodeWithSelector(VesperPoolV6_1.initializeV6_1.selector, 1);

        // Note calling directly on implementation and not through proxy
        vm.expectRevert("UUPSUnauthorizedCallContext()");
        pool.upgradeToAndCall(address(newImplementation), initData);
    }
}
