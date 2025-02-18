// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

interface IPositionManager {
    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH) external;

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH) external;

    function getSwapFees(bool zeroForOne, int256 amountSpecified) external view returns (uint256);
}

interface IPositionManagerStandard is IPositionManager {
    function setKParams(uint256 _k1, uint256 _k2) external;

    function setFees(uint256 _fees) external;
}
