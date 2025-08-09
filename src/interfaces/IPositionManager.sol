// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for a Position Manager.
interface IPositionManager {
    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH, uint160 sqrtPrice) external;

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH, uint160 sqrtPrice) external;
}
