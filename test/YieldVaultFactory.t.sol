// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {YieldVaultFactory} from "src/YieldVaultFactory.sol";
import {YieldVault} from "src/YieldVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants} from "test/helpers/Constants.sol";

contract YieldVaultFactoryTest is Test {
    YieldVaultFactory factory;
    YieldVault implementation;
    MockERC20 asset;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address newOwner = makeAddr("newOwner");

    string constant VAULT_NAME = "Yield Vault ETH";
    string constant VAULT_SYMBOL = "yvETH";

    function setUp() public {
        // Deploy implementation
        implementation = new YieldVault();

        // Deploy factory with owner
        vm.prank(owner);
        factory = new YieldVaultFactory(address(implementation), address(this));

        // Deploy mock asset
        asset = new MockERC20();
    }

    /*/////////////////////////////////////////////////////////////
                        Create Upgradable Vault Tests
    /////////////////////////////////////////////////////////////*/

    function test_createVault_upgradable() public {
        address vault = factory.createVault(VAULT_NAME, VAULT_SYMBOL, address(asset));

        assertNotEq(vault, address(0));
        assertNotEq(vault, address(implementation));

        // Verify vault is a proxy
        YieldVault vaultContract = YieldVault(vault);
        assertEq(vaultContract.asset(), address(asset));
        assertEq(vaultContract.name(), VAULT_NAME);
        assertEq(vaultContract.symbol(), VAULT_SYMBOL);
        assertEq(vaultContract.owner(), address(this)); // msg.sender is the test contract
    }

    function test_createVault_upgradable_differentAssets() public {
        MockERC20 asset2 = new MockERC20();

        address vault1 = factory.createVault(VAULT_NAME, VAULT_SYMBOL, address(asset));
        address vault2 = factory.createVault(VAULT_NAME, VAULT_SYMBOL, address(asset2));

        assertNotEq(vault1, vault2);

        YieldVault vaultContract1 = YieldVault(vault1);
        YieldVault vaultContract2 = YieldVault(vault2);

        assertEq(vaultContract1.asset(), address(asset));
        assertEq(vaultContract2.asset(), address(asset2));
    }

    /*/////////////////////////////////////////////////////////////
                    Update Implementation Tests
    /////////////////////////////////////////////////////////////*/

    function test_updateImplementation() public {
        YieldVault newImplementation = new YieldVault();

        vm.expectEmit(true, true, false, false);
        emit YieldVaultFactory.ImplementationUpdated(address(implementation), address(newImplementation));

        vm.prank(owner);
        factory.updateImplementation(address(newImplementation));

        assertEq(factory.implementation(), address(newImplementation));
    }

    function test_updateImplementation_revertWhen_callerIsNotOwner() public {
        YieldVault newImplementation = new YieldVault();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        factory.updateImplementation(address(newImplementation));
    }
}
