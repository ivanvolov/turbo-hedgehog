// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Defines the interface for a Rebalance Adapter.
interface IRebalanceAdapter {
    function sqrtPriceAtLastRebalance() external view returns (uint160);
}
