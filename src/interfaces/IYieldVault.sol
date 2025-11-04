// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IYieldVault {
    function asset() external view returns (address);

    function excessDebt(address strategy_) external view returns (uint256);

    function totalDebtOf(address strategy_) external view returns (uint256);

    function reportEarning(uint256 profit_, uint256 loss_, uint256 payback_) external;
}
