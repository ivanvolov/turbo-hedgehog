// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Id} from "@forks/morpho/IMorpho.sol";

interface ILendingAdapter {
    // Borrow market functions
    function getBorrowed() external view returns (uint256);

    function borrow(uint256 amountUSDC) external;

    function repay(uint256 amount) external;

    function getCollateral() external view returns (uint256);

    function removeCollateral(uint256 amount) external;

    function addCollateral(uint256 amount) external;

    // Provide market functions
    function getSupplied() external view returns (uint256);

    function supply(uint256 amount) external;

    function withdraw(uint256 amount) external;

    // Sync market functions
    function syncDeposit() external;

    function syncBorrow() external;

    // Params
    function setBorrowUSDCmId(Id) external;

    function setDepositUSDCmId(Id) external;

    function addAuthorizedCaller(address) external;
}
