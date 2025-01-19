// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

interface IPositionManager {
    error NotHook();

    function setHook(address _hook) external;

    function setLendingAdapter(address _lendingAdapter) external;

    function setRebalanceAdapter(address _rebalanceAdapter) external;

    function setKParams(uint256 _k1, uint256 _k2) external;

    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH) external;

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH) external;
}
