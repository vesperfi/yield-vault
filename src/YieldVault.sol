// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable as ERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable as ERC20Permit} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC4626Upgradeable as ERC4626} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Ownable2StepUpgradeable as Ownable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IVaultRewards} from "./interfaces/IVaultRewards.sol";
import {ShutdownableUpgradeable as Shutdownable} from "./ShutdownableUpgradeable.sol";

contract YieldVault is ERC4626, ERC20Permit, Ownable, Shutdownable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant MAX_BPS = 10_000;
    uint256 internal constant ONE_YEAR = 365.25 days;

    error AddInListFailed();
    error AddressIsNull();
    error AmountIsBelowDepositLimit();
    error ArrayLengthMismatch();
    error AssetsCanNotBeWithdrawn(uint256 _maxWithdrawable);
    error CallerIsNotKeeper();
    error CallerIsNotMaintainer();
    error FromTokenCannotBeAsset();
    error InputIsHigherThanMaxLimit();
    error InsufficientBalance();
    error InvalidDebtRatio();
    error MinimumDepositLimitCannotBeZero();
    error LossTooHigh();
    error OwnerMismatch(address, address);
    error RemoveFromListFailed();
    error StrategyIsActive();
    error StrategyIsNotActive();
    error TotalDebtShouldBeZero();
    error ZeroAssets();
    error ZeroShares();

    event EarningReported(
        address indexed strategy,
        uint256 profit,
        uint256 loss,
        uint256 payback,
        uint256 strategyDebt,
        uint256 vaultDebt,
        uint256 creditLine
    );
    event LossReported(address indexed strategy, uint256 loss);
    event StrategyAdded(address indexed strategy, uint256 debtRatio);
    event StrategyRemoved(address indexed strategy);
    event UniversalFeePaid(uint256 strategyDebt, uint256 profit, uint256 fee);
    event UpdatedMaximumProfitAsFee(uint256 oldMaxProfitAsFee, uint256 newMaxProfitAsFee);
    event UpdatedMinimumDepositLimit(uint256 oldDepositLimit, uint256 newDepositLimit);
    event UpdatedVaultRewards(address indexed previousVaultRewards, address indexed newVaultRewards);
    event UpdatedStrategyDebtRatio(address indexed strategy, uint256 oldDebtRatio, uint256 newDebtRatio);
    event UpdatedUniversalFee(uint256 oldUniversalFee, uint256 newUniversalFee);
    event UpdatedWithdrawQueue();

    /*/////////////////////////////////////////////////////////////
                                Storage
    /////////////////////////////////////////////////////////////*/
    struct StrategyConfig {
        bool active;
        uint256 lastRebalance; // Timestamp of last rebalance. It is used in universal fee calculation
        uint256 totalDebt; // Total outstanding debt strategy has
        uint256 totalLoss; // Total loss that strategy has realized
        uint256 totalProfit; // Total gain that strategy has realized
        uint256 debtRatio; // % of asset allocation
    }

    /// @custom:storage-location erc7201:vault.storage.YieldVault
    struct VaultStorage {
        // VaultRewards contract address
        address _vaultRewards;
        // List of keeper addresses
        EnumerableSet.AddressSet _keepers;
        // List of maintainer addresses
        EnumerableSet.AddressSet _maintainers;
        //Universal fee of this vault. Default to 2%
        uint256 _universalFee;
        // Maximum percentage of profit that can be counted as universal fee. Default to 50%
        uint256 _maxProfitAsFee;
        // Minimum deposit limit. Default to 1
        /// @dev Do not set it to 0 as deposit() is checking if amount >= limit
        uint256 _minimumDepositLimit;
        // Decimal offset. 18 - collateral asset decimal.
        uint8 _offset;
        // Total debt ratio.
        uint256 _totalDebtRatio;
        // Total debt. Sum of debt of all strategies.
        uint256 _totalDebt;
        EnumerableSet.AddressSet _strategies;
        // Array of strategy in the order in which funds should be withdrawn.
        address[] _withdrawQueue;
        // Strategy address to its configuration
        mapping(address strategy => StrategyConfig) _strategyConfig;
    }

    // keccak256(abi.encode(uint256(keccak256("vault.storage.YieldVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultStorageLocation = 0xbaeaf235c9c9807c1f4a2c352810dd4cb4b0d3d0f2cf0b692f9279e99df38e00;

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := VaultStorageLocation
        }
    }

    /*/////////////////////////////////////////////////////////////
                    Constructor and initialize
    /////////////////////////////////////////////////////////////*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address asset_, address owner_) public initializer {
        if (asset_ == address(0)) revert AddressIsNull();
        __ERC20_init(name_, symbol_);
        __ERC4626_init(IERC20(asset_));
        __ERC20Permit_init(name_);
        __Ownable_init(owner_);
        __Shutdownable_init();

        VaultStorage storage $ = _getVaultStorage();

        $._keepers.add(owner_);
        $._maintainers.add(owner_);
        $._universalFee = 200; // 2%
        $._maxProfitAsFee = 5_000; // 50%
        $._minimumDepositLimit = 1;
        // calculate decimal offset once
        $._offset = 18 - IERC20Metadata(asset_).decimals();
    }

    modifier onlyKeeper() {
        if (msg.sender != owner() && !isKeeper(msg.sender)) revert CallerIsNotKeeper();
        _;
    }

    modifier onlyMaintainer() {
        if (msg.sender != owner() && !isMaintainer(msg.sender)) revert CallerIsNotMaintainer();
        _;
    }

    /*/////////////////////////////////////////////////////////////
                            Getters
    /////////////////////////////////////////////////////////////*/

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    function excessDebt(address strategy_) external view returns (uint256) {
        return _excessDebt(_getVaultStorage()._strategyConfig[strategy_]);
    }

    function getStrategies() external view returns (address[] memory) {
        return _getVaultStorage()._strategies.values();
    }

    function getStrategyConfig(address strategy_) external view returns (StrategyConfig memory) {
        return _getVaultStorage()._strategyConfig[strategy_];
    }

    function getWithdrawQueue() external view returns (address[] memory) {
        return _getVaultStorage()._withdrawQueue;
    }

    function isKeeper(address address_) public view returns (bool) {
        return _getVaultStorage()._keepers.contains(address_);
    }

    function isMaintainer(address address_) public view returns (bool) {
        return _getVaultStorage()._maintainers.contains(address_);
    }

    function keepers() external view returns (address[] memory) {
        return _getVaultStorage()._keepers.values();
    }

    function maintainers() external view returns (address[] memory) {
        return _getVaultStorage()._maintainers.values();
    }

    function maxProfitAsFee() external view returns (uint256) {
        return _getVaultStorage()._maxProfitAsFee;
    }

    function minimumDepositLimit() external view returns (uint256) {
        return _getVaultStorage()._minimumDepositLimit;
    }

    function vaultRewards() external view returns (address) {
        return _getVaultStorage()._vaultRewards;
    }

    function pricePerShare() public view returns (uint256) {
        return convertToAssets(1e18);
    }

    function totalAssets() public view override returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        return $._totalDebt + super.totalAssets();
    }

    function totalDebt() external view returns (uint256) {
        return _getVaultStorage()._totalDebt;
    }

    function totalDebtOf(address strategy_) external view returns (uint256) {
        return _getVaultStorage()._strategyConfig[strategy_].totalDebt;
    }

    function totalDebtRatio() external view returns (uint256) {
        return _getVaultStorage()._totalDebtRatio;
    }

    function universalFee() external view returns (uint256) {
        return _getVaultStorage()._universalFee;
    }

    function version() external pure returns (string memory) {
        return "6.0.0";
    }

    /// Below functions are added for compatibility with V6 strategies
    /// @notice This function is needed for compatibility with V6 strategies.
    /// @return owner address
    function governor() external view returns (address) {
        return owner();
    }

    /// @notice This function is needed for compatibility with V6 strategies.
    /// @return asset address
    function token() external view returns (address) {
        return asset();
    }

    /*/////////////////////////////////////////////////////////////
                            User functions
    /////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        if (assets < _getVaultStorage()._minimumDepositLimit) revert AmountIsBelowDepositLimit();
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        uint256 _assets = previewMint(shares);
        if (_assets < _getVaultStorage()._minimumDepositLimit) revert AmountIsBelowDepositLimit();
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626
    function withdraw(uint256 assets_, address receiver_, address owner_) public override returns (uint256) {
        _beforeWithdraw(assets_);
        return super.withdraw(assets_, receiver_, owner_);
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 shares_, address receiver_, address owner_) public override returns (uint256) {
        if (shares_ == 0) revert ZeroShares();
        _beforeWithdraw(previewRedeem(shares_));
        return super.redeem(shares_, receiver_, owner_);
    }

    /*/////////////////////////////////////////////////////////////
                            Strategy functions
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice onlyStrategy:: Strategy call this in regular interval. Only strategy function.
     * @param profit_ yield generated by strategy. Strategy get performance fee on this amount
     * @param loss_  Reduce debt ,also reduce debtRatio, increase loss in record.
     * @param payback_ strategy willing to payback outstanding above debtLimit. no performance fee on this amount.
     *  when governance has reduced debtRatio of strategy, strategy will report profit and payback amount separately.
     */
    function reportEarning(uint256 profit_, uint256 loss_, uint256 payback_) external {
        VaultStorage storage $ = _getVaultStorage();
        address _strategy = msg.sender;

        StrategyConfig storage _config = $._strategyConfig[_strategy];

        if (!_config.active) revert StrategyIsNotActive();
        if (IERC20(asset()).balanceOf(_strategy) < (profit_ + payback_)) revert InsufficientBalance();

        // handle universal fee
        if (profit_ > 0) {
            _config.totalProfit += profit_;
            uint256 _fee = _calculateUniversalFee($, _strategy, profit_);
            // Mint shares equal to universal fee
            if (_fee > 0) {
                _mint(IStrategy(_strategy).feeCollector(), convertToShares(_fee));
                emit UniversalFeePaid(_config.totalDebt, profit_, _fee);
            }
        }

        if (loss_ > 0) {
            _reportLoss($, _strategy, loss_);
        }

        uint256 _actualPayback = Math.min(_excessDebt(_config), payback_);
        if (_actualPayback > 0) {
            _config.totalDebt -= _actualPayback;
            $._totalDebt -= _actualPayback;
        }

        uint256 _creditLine = _availableCreditLimit(_config, $._totalDebtRatio, $._totalDebt);
        if (_creditLine > 0) {
            _config.totalDebt += _creditLine;
            $._totalDebt += _creditLine;
        }

        // update rebalance timestamp
        _config.lastRebalance = block.timestamp;

        uint256 _totalPayback = profit_ + _actualPayback;
        // After payback, if strategy has credit line available then send more fund to strategy
        // If payback is more than available credit line then get fund from strategy
        if (_totalPayback < _creditLine) {
            IERC20(asset()).safeTransfer(_strategy, _creditLine - _totalPayback);
        } else if (_totalPayback > _creditLine) {
            IERC20(asset()).safeTransferFrom(_strategy, address(this), _totalPayback - _creditLine);
        }

        emit EarningReported(_strategy, profit_, loss_, _actualPayback, _config.totalDebt, $._totalDebt, _creditLine);
    }

    /**
     * @notice onlyStrategy:: Report loss outside of rebalance activity.
     * @dev Some strategies pay deposit fee thus realizing loss at deposit.
     * For example: Curve's 3vault has some slippage due to deposit of one asset in 3vault.
     * Strategy may want report this loss instead of waiting for next rebalance.
     * @param loss_ Loss that strategy want to report
     */
    function reportLoss(uint256 loss_) external {
        if (loss_ > 0) {
            VaultStorage storage $ = _getVaultStorage();
            if (!$._strategyConfig[msg.sender].active) revert StrategyIsNotActive();
            _reportLoss($, msg.sender, loss_);
            emit LossReported(msg.sender, loss_);
        }
    }

    /*/////////////////////////////////////////////////////////////
                            Owner functions
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice onlyOwner:: Add strategy. Once strategy is added it can call rebalance and
     * borrow fund from vault and invest that fund in provider/lender.
     * @dev Recalculate vault level external deposit fee after all state variables are updated.
     * @param strategy_ Strategy address
     * @param debtRatio_ Vault fund allocation to this strategy
     */
    function addStrategy(address strategy_, uint256 debtRatio_) public onlyOwner {
        if (strategy_ == address(0)) revert AddressIsNull();

        VaultStorage storage $ = _getVaultStorage();
        if ($._strategyConfig[strategy_].active) revert StrategyIsActive();
        $._totalDebtRatio = $._totalDebtRatio + debtRatio_;
        if ($._totalDebtRatio > MAX_BPS) revert InvalidDebtRatio();

        StrategyConfig memory newStrategy = StrategyConfig({
            active: true,
            lastRebalance: block.timestamp,
            totalDebt: 0,
            totalLoss: 0,
            totalProfit: 0,
            debtRatio: debtRatio_
        });
        $._strategyConfig[strategy_] = newStrategy;
        $._strategies.add(strategy_);
        $._withdrawQueue.push(strategy_);
        emit StrategyAdded(strategy_, debtRatio_);
    }

    /**
     * @notice onlyOwner:: Remove strategy.
     * @dev If strategy has non-zero debt then it can NOT be removed.
     * @dev Removal of strategy will lead to update in withdraw queue as well. Make sure
     * order of withdraw queue remains same.
     * @param strategy_ address of strategy to remove.
     */
    function removeStrategy(address strategy_) external onlyOwner {
        VaultStorage storage $ = _getVaultStorage();
        StrategyConfig memory _strategyToRemove = $._strategyConfig[strategy_];
        if (!_strategyToRemove.active) revert StrategyIsNotActive();
        if (_strategyToRemove.totalDebt != 0) revert TotalDebtShouldBeZero();
        // Adjust totalDebtRatio
        $._totalDebtRatio -= _strategyToRemove.debtRatio;
        // Remove strategy
        delete $._strategyConfig[strategy_];
        $._strategies.remove(strategy_);
        // use new length of _strategies to create new withdraw queue
        address[] memory _withdrawQueue = new address[]($._strategies.length());
        // After removal of strategy, withdrawQueue.length > strategies.length
        address[] memory _currentWithdrawQueue = $._withdrawQueue;
        uint256 _len = _currentWithdrawQueue.length;
        uint256 j;
        for (uint256 i; i < _len; i++) {
            if (_currentWithdrawQueue[i] != strategy_) {
                _withdrawQueue[j] = _currentWithdrawQueue[i];
                j++;
            }
        }
        $._withdrawQueue = _withdrawQueue;
        emit StrategyRemoved(strategy_);
    }

    /**
     * @notice onlyOwner:: Transfer given ERC20 token to given address
     * @param fromToken_ Token address to sweep
     * @param to_ address where tokens will be sent
     */
    function sweep(address fromToken_, address to_) external onlyOwner {
        if (to_ == address(0)) revert AddressIsNull();
        if (fromToken_ == asset()) revert FromTokenCannotBeAsset();
        IERC20(fromToken_).safeTransfer(to_, IERC20(fromToken_).balanceOf(address(this)));
    }

    /**
     * @notice OnlyOwner:: Update maximum profit that can be used as universal fee
     * @param newMaxProfitAsFee_ New max profit as fee
     */
    function updateMaximumProfitAsFee(uint256 newMaxProfitAsFee_) external onlyOwner {
        if (newMaxProfitAsFee_ > MAX_BPS) revert InputIsHigherThanMaxLimit();

        VaultStorage storage $ = _getVaultStorage();
        emit UpdatedMaximumProfitAsFee($._maxProfitAsFee, newMaxProfitAsFee_);
        $._maxProfitAsFee = newMaxProfitAsFee_;
    }

    /**
     * @notice OnlyOwner:: Update minimum deposit limit
     * @param newLimit_ New minimum deposit limit
     */
    function updateMinimumDepositLimit(uint256 newLimit_) external onlyOwner {
        if (newLimit_ == 0) revert MinimumDepositLimitCannotBeZero();

        VaultStorage storage $ = _getVaultStorage();
        emit UpdatedMinimumDepositLimit($._minimumDepositLimit, newLimit_);
        $._minimumDepositLimit = newLimit_;
    }

    /**
     * @notice OnlyOwner:: Update vault rewards address for this vault
     * @param newVaultRewards_ new vault rewards address
     */
    function updateVaultRewards(address newVaultRewards_) external onlyOwner {
        if (newVaultRewards_ == address(0)) revert AddressIsNull();

        VaultStorage storage $ = _getVaultStorage();
        emit UpdatedVaultRewards($._vaultRewards, newVaultRewards_);
        $._vaultRewards = newVaultRewards_;
    }

    /**
     * @notice OnlyOwner:: Update universal fee for this vault
     * @dev Format: 1500 = 15% fee, 100 = 1%
     * @param newUniversalFee_ new universal fee
     */
    function updateUniversalFee(uint256 newUniversalFee_) external onlyOwner {
        if (newUniversalFee_ > MAX_BPS) revert InputIsHigherThanMaxLimit();

        VaultStorage storage $ = _getVaultStorage();
        emit UpdatedUniversalFee($._universalFee, newUniversalFee_);
        $._universalFee = newUniversalFee_;
    }

    /*/////////////////////////////////////////////////////////////
                            Keeper functions
    /////////////////////////////////////////////////////////////*/

    function pause() external onlyKeeper {
        _pause();
    }

    function unpause() external onlyKeeper {
        _unpause();
    }

    function shutdown() external onlyKeeper {
        _shutdown();
    }

    function restart() external onlyKeeper {
        _restart();
    }

    /**
     * @notice Add given address in keepers list.
     * @param keeperAddress_ keeper address to add.
     */
    function addKeeper(address keeperAddress_) external onlyKeeper {
        if (!_getVaultStorage()._keepers.add(keeperAddress_)) revert AddInListFailed();
    }

    /**
     * @notice Remove given address from keepers list.
     * @param keeperAddress_ keeper address to remove.
     */
    function removeKeeper(address keeperAddress_) external onlyKeeper {
        if (!_getVaultStorage()._keepers.remove(keeperAddress_)) revert RemoveFromListFailed();
    }

    /**
     * @notice Add given address in maintainers list.
     * @param maintainerAddress_ maintainer address to add.
     */
    function addMaintainer(address maintainerAddress_) external onlyKeeper {
        if (!_getVaultStorage()._maintainers.add(maintainerAddress_)) revert AddInListFailed();
    }

    /**
     * @notice Remove given address from maintainers list.
     * @param maintainerAddress_ maintainer address to remove.
     */
    function removeMaintainer(address maintainerAddress_) external onlyKeeper {
        if (!_getVaultStorage()._maintainers.remove(maintainerAddress_)) revert RemoveFromListFailed();
    }

    /*/////////////////////////////////////////////////////////////
                            Maintainer functions
    /////////////////////////////////////////////////////////////*/

    /**
     * @notice onlyMaintainer:: Update debt ratio.
     * @dev A strategy is retired when debtRatio is 0
     * @dev As debtRatio impacts vault level external deposit fee hence recalculate it after updating debtRatio.
     * @param strategy_ Strategy address for which debt ratio is being updated
     * @param debtRatio_ New debt ratio
     */
    function updateDebtRatio(address strategy_, uint256 debtRatio_) external onlyMaintainer {
        VaultStorage storage $ = _getVaultStorage();
        StrategyConfig storage _config = $._strategyConfig[strategy_];
        if (!_config.active) revert StrategyIsNotActive();
        // Update totalDebtRatio
        $._totalDebtRatio = ($._totalDebtRatio - _config.debtRatio) + debtRatio_;
        if ($._totalDebtRatio > MAX_BPS) revert InvalidDebtRatio();
        emit UpdatedStrategyDebtRatio(strategy_, _config.debtRatio, debtRatio_);
        // Write to storage
        _config.debtRatio = debtRatio_;
    }

    /**
     * @notice onlyMaintainer:: Update withdraw queue.
     * @dev The vault typically maintains a buffer to satisfy withdrawal requests.
     * Any request exceeding the buffer level will be processed through the withdrawQueue.
     * In this case, withdrawQueue[0] will be the first strategy to receive the withdrawal request.
     * @param withdrawQueue_ List of strategy ordered by withdrawal priority.
     */
    function updateWithdrawQueue(address[] memory withdrawQueue_) external onlyMaintainer {
        VaultStorage storage $ = _getVaultStorage();
        uint256 _length = withdrawQueue_.length;
        if (_length != $._withdrawQueue.length || _length != $._strategies.length()) revert ArrayLengthMismatch();
        for (uint256 i; i < _length; i++) {
            if (!$._strategyConfig[withdrawQueue_[i]].active) revert StrategyIsNotActive();
        }
        $._withdrawQueue = withdrawQueue_;
        emit UpdatedWithdrawQueue();
    }

    /*/////////////////////////////////////////////////////////////
                            Internal functions
    /////////////////////////////////////////////////////////////*/

    function _beforeWithdraw(uint256 assets_) internal whenNotShutdown {
        if (assets_ == 0) revert ZeroAssets();
        uint256 _assetsHere = _assetsInVault();
        // If we do not have enough assets in vault then withdraw from strategy.
        if (assets_ > _assetsHere) {
            // Strategy may withdraw less than requested
            _assetsHere = _assetsHere + _withdrawFromStrategy(assets_ - _assetsHere);
            if (assets_ > _assetsHere) revert AssetsCanNotBeWithdrawn(_assetsHere);
        }
    }

    /**
     * @dev When strategy report loss, its debtRatio decreases to get fund back quickly.
     * Reduction is debt ratio is reduction in credit limit
     */
    function _reportLoss(VaultStorage storage $, address strategy_, uint256 loss_) internal {
        StrategyConfig storage _config = $._strategyConfig[strategy_];
        if (_config.totalDebt < loss_) revert LossTooHigh();
        // increase loss of strategy
        _config.totalLoss += loss_;
        // decrease debt for strategy and vault aka global
        _config.totalDebt -= loss_;
        $._totalDebt -= loss_;

        // calculate change in debtRatio
        uint256 _deltaDebtRatio = Math.min((loss_ * MAX_BPS) / totalAssets(), _config.debtRatio);
        // decrease debtRatio for strategy and vault aka global
        _config.debtRatio -= _deltaDebtRatio;
        $._totalDebtRatio -= _deltaDebtRatio;
    }

    function _withdrawFromStrategy(uint256 assets_) internal returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        // Withdraw assets from queue
        IERC20 _asset = IERC20(asset());
        uint256 _debt;
        uint256 _balanceBefore;
        uint256 _assetsWithdrawn;
        uint256 _totalAssetsWithdrawn;
        address[] memory _withdrawQueue = $._withdrawQueue;
        uint256 _len = _withdrawQueue.length;
        for (uint256 i; i < _len; i++) {
            uint256 _assetsNeeded = assets_ - _totalAssetsWithdrawn;
            address _currentStrategy = _withdrawQueue[i];
            _debt = $._strategyConfig[_currentStrategy].totalDebt;
            if (_debt == 0) {
                continue;
            }
            if (_assetsNeeded > _debt) {
                // Should not withdraw more than current debt of strategy.
                _assetsNeeded = _debt;
            }
            _balanceBefore = _asset.balanceOf(address(this));
            // solhint-disable no-empty-blocks
            try IStrategy(_currentStrategy).withdraw(_assetsNeeded) {} catch {
                continue;
            }
            _assetsWithdrawn = _asset.balanceOf(address(this)) - _balanceBefore;

            // To be on safe side, take a min of strategy debt and withdrawn.
            uint256 _debtToReduce = Math.min(_debt, _assetsWithdrawn);
            // update strategy debt and global debt
            $._strategyConfig[_currentStrategy].totalDebt -= _debtToReduce;
            $._totalDebt -= _debtToReduce;

            _totalAssetsWithdrawn += _assetsWithdrawn;

            if (_totalAssetsWithdrawn >= assets_) {
                // withdraw done
                break;
            }
        }
        return _totalAssetsWithdrawn;
    }

    /**
     * @dev Overridden ERC20 _update() to updateReward() before mint, burn and transfer.
     */
    function _update(address from, address to, uint256 value) internal override(ERC20) {
        address _vaultRewards = _getVaultStorage()._vaultRewards;
        if (_vaultRewards != address(0)) {
            if (from != address(0)) {
                IVaultRewards(_vaultRewards).updateReward(from);
            }
            if (to != address(0)) {
                IVaultRewards(_vaultRewards).updateReward(to);
            }
        }
        ERC20._update(from, to, value);
    }

    /*/////////////////////////////////////////////////////////////
                        Internal view functions
    /////////////////////////////////////////////////////////////*/

    function _assetsInVault() internal view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function _availableCreditLimit(
        StrategyConfig memory config_,
        uint256 totalDebtRatio_,
        uint256 totalDebt_
    ) internal view returns (uint256) {
        if (isShutdown()) {
            return 0;
        }
        uint256 _totalValue = totalAssets();
        uint256 _strategyDebtLimit = (config_.debtRatio * _totalValue) / MAX_BPS;
        uint256 _currentDebt = config_.totalDebt;
        if (_currentDebt >= _strategyDebtLimit) {
            return 0;
        }

        uint256 _vaultDebtLimit = (totalDebtRatio_ * _totalValue) / MAX_BPS;
        if (totalDebt_ >= _vaultDebtLimit) {
            return 0;
        }
        // take min of available debt at strategy level and at vault level.
        uint256 _available = Math.min((_strategyDebtLimit - _currentDebt), (_vaultDebtLimit - totalDebt_));
        // take min of asset balance here and available
        return Math.min(_assetsInVault(), _available);
    }

    /**
     * @dev Calculate universal fee based on strategy's TVL, profit earned and duration between rebalance and now.
     */
    function _calculateUniversalFee(
        VaultStorage storage $,
        address strategy_,
        uint256 profit_
    ) private view returns (uint256 _fee) {
        StrategyConfig memory _config = $._strategyConfig[strategy_];
        _fee = ($._universalFee * (block.timestamp - _config.lastRebalance) * _config.totalDebt) / (MAX_BPS * ONE_YEAR);
        uint256 _maxFee = (profit_ * $._maxProfitAsFee) / MAX_BPS;
        if (_fee > _maxFee) {
            _fee = _maxFee;
        }
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return _getVaultStorage()._offset;
    }

    function _excessDebt(StrategyConfig memory config_) internal view returns (uint256) {
        uint256 _currentDebt = config_.totalDebt;
        if (isShutdown()) {
            return _currentDebt;
        }
        uint256 _maxDebt = (config_.debtRatio * totalAssets()) / MAX_BPS;
        return _currentDebt > _maxDebt ? (_currentDebt - _maxDebt) : 0;
    }

    /*/////////////////////////////////////////////////////////////
                        upgrade control functions
    /////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable override onlyProxy {
        address _ownerBefore = owner();
        super.upgradeToAndCall(newImplementation, data);
        // owner should be same before and after upgrade.
        address _ownerAfter = owner();
        if (_ownerAfter != _ownerBefore) revert OwnerMismatch(_ownerAfter, _ownerBefore);
    }
}
