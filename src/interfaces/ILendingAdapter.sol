// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** interfaces
import {Id} from "@forks/morpho/IMorpho.sol";

interface ILendingAdapter {
    // ** Flashloan
    function flashLoanSingle(address token, uint256 amount, bytes calldata data) external;

    function flashLoanTwoTokens(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        bytes calldata data
    ) external;

    // ** Long market
    function getBorrowedLong() external view returns (uint256);

    function borrowLong(uint256 amountUSDC) external;

    function repayLong(uint256 amountUSDC) external;

    function getCollateralLong() external view returns (uint256);

    function removeCollateralLong(uint256 amountWETH) external;

    function addCollateralLong(uint256 amountWETH) external;

    // ** Short market
    function getBorrowedShort() external view returns (uint256);

    function borrowShort(uint256 amountWETH) external;

    function repayShort(uint256 amountWETH) external;

    function getCollateralShort() external view returns (uint256);

    function removeCollateralShort(uint256 amountUSDC) external;

    function addCollateralShort(uint256 amountUSDC) external;

    // ** Helpers
    function syncLong() external;

    function syncShort() external;
}

interface IFlashLoanReceiver {
    function onFlashLoanSingle(address token, uint256 amount, bytes calldata data) external;

    function onFlashLoanTwoTokens(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1,
        bytes calldata data
    ) external;
}
