// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for a Position Manager.
interface IPositionManager {
    error ProtocolFeeTooLarge(uint24 fee);

    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH) external;

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH) external;

    function getSwapFees(bool zeroForOne, int256 amountSpecified) external view returns (uint24);
}

/// @notice Interface for all standard position manager setters.
interface IPositionManagerStandard is IPositionManager {
    function setKParams(uint256 _k1, uint256 _k2) external;

    function setFees(uint24 _fees) external;
}
