// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for a Position Manager.
interface IPositionManager {
    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH) external;

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH) external;
}

/// @notice Interface for all standard position manager setters.
interface IPositionManagerStandard is IPositionManager {
    function setKParams(uint256 _k1, uint256 _k2) external;
}
