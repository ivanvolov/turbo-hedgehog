// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** contracts
import {OracleBase} from "./OracleBase.sol";

/// @title Oracle
/// @notice Implementation of the Chainlink based oracle with two feeds.
contract Oracle is OracleBase, Ownable {
    error StalenessThresholdExceeded();
    error PriceNotValid();

    event StalenessThresholdsSet(uint256 stalenessThresholdB, uint256 stalenessThresholdQ);

    struct StalenessThresholds {
        uint128 base;
        uint128 quote;
    }

    AggregatorV3Interface public immutable feedBase;
    AggregatorV3Interface public immutable feedQuote;
    StalenessThresholds public stalenessThresholds;

    constructor(
        AggregatorV3Interface _feedBase,
        AggregatorV3Interface _feedQuote,
        bool _isInvertedPool,
        int256 _tokenDecimalsDelta
    )
        OracleBase(
            _isInvertedPool,
            _tokenDecimalsDelta + int256(int8(_feedBase.decimals())) - int256(int8(_feedQuote.decimals()))
        )
        Ownable(msg.sender)
    {
        feedBase = _feedBase;
        feedQuote = _feedQuote;
    }

    function setStalenessThresholds(uint128 thresholdBase, uint128 thresholdQuote) external onlyOwner {
        stalenessThresholds = StalenessThresholds(thresholdBase, thresholdQuote);
        emit StalenessThresholdsSet(thresholdBase, thresholdQuote);
    }

    function _fetchAssetsPrices() internal view override returns (uint256, uint256) {
        StalenessThresholds memory thresholds = stalenessThresholds;

        (, int256 _priceBase, , uint256 updatedAtBase, ) = feedBase.latestRoundData();
        if (updatedAtBase + thresholds.base < block.timestamp) revert StalenessThresholdExceeded();

        (, int256 _priceQuote, , uint256 updatedAtQuote, ) = feedQuote.latestRoundData();
        if (updatedAtQuote + thresholds.quote < block.timestamp) revert StalenessThresholdExceeded();

        if (_priceBase <= 0 || _priceQuote <= 0) revert PriceNotValid();
        return (uint256(_priceBase), uint256(_priceQuote));
    }
}
