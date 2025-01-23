// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** interfaces
import {Id} from "@forks/morpho/IMorpho.sol";

interface ILendingAdapter {
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

    // ** Params
    function addAuthorizedCaller(address) external;

    function setTokens(address, address, uint8, uint8) external;
}
