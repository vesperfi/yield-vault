// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

interface IStrategy {
    function rebalance() external returns (uint256 _profit, uint256 _loss, uint256 _payback);

    function withdraw(uint256 _amount) external;

    function feeCollector() external view returns (address);

    function vault() external view returns (address);
}
