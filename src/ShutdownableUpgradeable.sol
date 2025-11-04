// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @dev This contract extends functionalities of OpenZeppelin Pausable by adding 'stopped' state.
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotShutdown` and `whenShutdown`, which can be applied to
 * the functions of your contract. Note that they will not be shutdownable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract ShutdownableUpgradeable is PausableUpgradeable {
    /// @custom:storage-location erc7201:vault.storage.Shutdownable
    struct ShutdownableStorage {
        bool _stopped;
    }

    // keccak256(abi.encode(uint256(keccak256("vault.storage.Shutdownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ShutdownableStorageLocation =
        0x019a888e50c7391e6e8fcd7763e66682aa228549857b7d24cf4bc363dd4e7100;

    function _getShutdownableStorage() private pure returns (ShutdownableStorage storage $) {
        assembly {
            $.slot := ShutdownableStorageLocation
        }
    }

    /**
     * @dev Emitted when the shutdown is triggered by `account`.
     */
    event Shutdown(address account);

    /**
     * @dev Emitted when the shutdown is lifted by `account`.
     */
    event Restart(address account);

    /**
     * @dev The operation failed because the contract is shutdown.
     */
    error EnforcedShutdown();

    /**
     * @dev The operation failed because the contract is not shutdown.
     */
    error ExpectedShutdown();

    /**
     * @dev Initializes the contract in start state.
     */
    function __Shutdownable_init() internal onlyInitializing {
        __Shutdownable_init_unchained();
    }

    function __Shutdownable_init_unchained() internal onlyInitializing {
        ShutdownableStorage storage $ = _getShutdownableStorage();
        $._stopped = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not shutdown.
     *
     * Requirements:
     *
     * - The contract must not be shutdown.
     */
    modifier whenNotShutdown() {
        _requireNotShutdown();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is shutdown.
     *
     * Requirements:
     *
     * - The contract must be shutdown.
     */
    modifier whenShutdown() {
        _requireShutdown();
        _;
    }

    /**
     * @dev Returns true if the contract is paused or shutdown, and false otherwise.
     */
    function paused() public view override returns (bool) {
        return super.paused() || isShutdown();
    }

    /**
     * @dev Returns true if the contract is shutdown, and false otherwise.
     */
    function isShutdown() public view virtual returns (bool) {
        ShutdownableStorage storage $ = _getShutdownableStorage();
        return $._stopped;
    }

    /**
     * @dev Throws if the contract is shutdown.
     */
    function _requireNotShutdown() internal view virtual {
        if (isShutdown()) {
            revert EnforcedShutdown();
        }
    }

    /**
     * @dev Throws if the contract is not shutdown.
     */
    function _requireShutdown() internal view virtual {
        if (!isShutdown()) {
            revert ExpectedShutdown();
        }
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     * - The contract must not be shutdown.
     */
    function _unpause() internal override whenNotShutdown whenPaused {
        super._unpause();
    }

    /**
     * @dev Triggers stopped state. This will also trigger pause.
     *
     * Requirements:
     *
     * - The contract must not be shutdown.
     */
    function _shutdown() internal virtual whenNotShutdown {
        ShutdownableStorage storage $ = _getShutdownableStorage();
        $._stopped = true;
        emit Shutdown(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be shutdown.
     */
    function _restart() internal virtual whenShutdown {
        ShutdownableStorage storage $ = _getShutdownableStorage();
        $._stopped = false;
        emit Restart(_msgSender());
    }
}
