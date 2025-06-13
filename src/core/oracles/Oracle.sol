// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** contracts
import {OracleBase} from "./OracleBase.sol";

/// @title Oracle
/// @notice Implementation of the Chainlink based oracle.
contract Oracle is OracleBase {
    AggregatorV3Interface internal immutable feedBase;
    AggregatorV3Interface internal immutable feedQuote;
    uint256 public immutable stalenessThresholdB;
    uint256 public immutable stalenessThresholdQ;

    constructor(
        AggregatorV3Interface _feedBase,
        AggregatorV3Interface _feedQuote,
        uint256 _stalenessThresholdB,
        uint256 _stalenessThresholdQ,
        bool _isInvertedPool,
        int8 _decimalsDelta
    ) OracleBase(_isInvertedPool, _decimalsDelta, _feedBase.decimals(), _feedQuote.decimals()) {
        feedBase = _feedBase;
        feedQuote = _feedQuote;

        stalenessThresholdB = _stalenessThresholdB;
        stalenessThresholdQ = _stalenessThresholdQ;
    }

    function _fetchAssetsPrices() internal view override returns (uint256, uint256) {
        (, int256 _priceBase, , uint256 updatedAtBase, ) = feedBase.latestRoundData();
        require(block.timestamp - updatedAtBase <= stalenessThresholdB, "O4");

        (, int256 _priceQuote, , uint256 updatedAtQuote, ) = feedQuote.latestRoundData();
        require(block.timestamp - updatedAtQuote <= stalenessThresholdQ, "O5");

        require(_priceBase > 0 && _priceQuote > 0, "O6");
        return (uint256(_priceBase), uint256(_priceQuote));
    }
}
