// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for an Oracle.
interface IOracle {
    function price() external view returns (uint256);
}
