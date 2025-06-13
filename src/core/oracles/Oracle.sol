// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** contracts
import {OracleBase} from "./OracleBase.sol";

contract Oracle is OracleBase {
    AggregatorV3Interface internal immutable feedBase;
    AggregatorV3Interface internal immutable feedQuote;
    uint256 public immutable stalenessThresholdQ;
    uint256 public immutable stalenessThresholdB;

    constructor(
        bool _isInvertedPool,
        uint8 _bDec,
        uint8 _qDec,
        AggregatorV3Interface _feedQuote,
        AggregatorV3Interface _feedBase,
        uint256 _stalenessThresholdQ,
        uint256 _stalenessThresholdB
    ) OracleBase(_isInvertedPool, _bDec, _qDec) {
        feedQuote = _feedQuote;
        feedBase = _feedBase;
        stalenessThresholdQ = _stalenessThresholdQ;
        stalenessThresholdB = _stalenessThresholdB;
        decimalsQuote = feedQuote.decimals();
        decimalsBase = feedBase.decimals();
    }

    function _fetchAssetsPrices() internal view override returns (uint256, uint256) {
        (, int256 _priceQuote, , uint256 updatedAtQuote, ) = feedQuote.latestRoundData();
        require(block.timestamp - updatedAtQuote <= stalenessThresholdQ, "O1");

        (, int256 _priceBase, , uint256 updatedAtBase, ) = feedBase.latestRoundData();
        require(block.timestamp - updatedAtBase <= stalenessThresholdB, "O2");

        require(_priceQuote > 0 && _priceBase > 0, "O3");
        return (uint256(_priceQuote), uint256(_priceBase));
    }
}
