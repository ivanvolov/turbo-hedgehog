// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** external imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Defines the interface for a Lending Adapter.
interface ILendingAdapter {
    // ** Position management
    function getPosition() external view returns (uint256, uint256, uint256, uint256);

    function updatePosition(int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS) external;

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
    function syncPositions() external;
}
