// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for an Oracle.
interface IOracle {
    error TotalDecimalsDeltaNotValid();
    error PriceZero();
    error SqrtPriceNotValid();

    function price() external view returns (uint256);

    function poolPrice() external view returns (uint256, uint160);
}
