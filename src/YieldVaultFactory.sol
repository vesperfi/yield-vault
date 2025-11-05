// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {YieldVault} from "./YieldVault.sol";

/**
 * @title YieldVaultFactory
 * @notice Factory contract for creating YieldVault instances with owner controls
 * @dev Owner can update the implementation address for proxy deployments
 */
contract YieldVaultFactory is Ownable2Step {
    /// @notice Address of the YieldVault implementation contract (for proxy deployments)
    address public implementation;

    /// @notice Emitted when a new upgradable vault is created
    /// @param vault Address of the newly created vault proxy
    /// @param name Name of the vault token
    /// @param symbol Symbol of the vault token
    /// @param asset Address of the underlying asset
    /// @param creator Address that created the vault
    event UpgradableVaultCreated(
        address indexed vault,
        string name,
        string symbol,
        address indexed asset,
        address indexed creator
    );

    /// @notice Emitted when the implementation address is updated
    /// @param oldImplementation Previous implementation address
    /// @param newImplementation New implementation address
    event ImplementationUpdated(address indexed oldImplementation, address indexed newImplementation);

    error AddressIsNull();

    /**
     * @notice Constructor sets the YieldVault implementation address and initial owner
     * @param implementation_ Address of the YieldVault implementation contract (for proxy deployments)
     * @param owner_ Address of the initial owner
     */
    constructor(address implementation_, address owner_) Ownable(owner_) {
        if (implementation_ == address(0)) revert AddressIsNull();
        implementation = implementation_;
    }

    /**
     * @notice Updates the YieldVault implementation address
     * @dev Only callable by the owner
     * @param newImplementation_ Address of the new YieldVault implementation contract
     */
    function updateImplementation(address newImplementation_) external onlyOwner {
        if (newImplementation_ == address(0)) revert AddressIsNull();
        address oldImplementation = implementation;
        implementation = newImplementation_;
        emit ImplementationUpdated(oldImplementation, newImplementation_);
    }

    /**
     * @notice Creates a new upgradable YieldVault
     * @param name_ Name of the vault token (e.g., "Vesper vault USDC")
     * @param symbol_ Symbol of the vault token (e.g., "vUSDC")
     * @param asset_ Address of the underlying asset (ERC20 token)
     * @return vault Address of the newly created vault
     */
    function createVault(string memory name_, string memory symbol_, address asset_) public returns (address vault) {
        if (asset_ == address(0)) revert AddressIsNull();

        // Create upgradable vault using ERC1967Proxy
        bytes memory initData = abi.encodeWithSignature(
            "initialize(string,string,address,address)",
            name_,
            symbol_,
            asset_,
            msg.sender
        );
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        vault = address(proxy);
        emit UpgradableVaultCreated(vault, name_, symbol_, asset_, msg.sender);

        return vault;
    }
}
