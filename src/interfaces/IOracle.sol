// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for an Oracle.
interface IOracle {
    error TokenDecimalsDeltaNotValid();
    error FeedDecimalsDeltaNotValid();
    error PriceZero();

    event StalenessThresholdsSet(uint256 stalenessThresholdB, uint256 stalenessThresholdQ);

    struct StalenessThresholds {
        uint128 base;
        uint128 quote;
    }

    function setStalenessThresholds(uint128, uint128) external;

    function price() external view returns (uint256);

    function poolPrice() external view returns (uint256, uint160);
}
