 // // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.0;

// // ** External imports
// import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// // ** contracts
// import {OracleBase} from "./OracleBase.sol";

// /// @title Oracle
// /// @notice Implementation of the Chainlink based oracle with one feed.
// contract OracleOneFeed is OracleBase {
//     error StalenessThresholdExceeded();
//     error PriceNotValid();

//     AggregatorV3Interface public immutable feedBase;
//     AggregatorV3Interface public immutable feedQuote;

//     constructor(
//         AggregatorV3Interface _feedBase,
//         AggregatorV3Interface _feedQuote,
//         bool _isInvertedPool,
//         int8 _tokenDecimalsDelta
//     ) OracleBase(_isInvertedPool, _tokenDecimalsDelta, int8(_feedBase.decimals()) - int8(_feedQuote.decimals())) {
//         feedBase = _feedBase;
//         feedQuote = _feedQuote;
//     }

//     function _fetchAssetsPrices() internal view override returns (uint256, uint256) {
//         StalenessThresholds memory thresholds = stalenessThresholds;

//         (, int256 _priceBase, , uint256 updatedAtBase, ) = feedBase.latestRoundData();
//         if (updatedAtBase + thresholds.base < block.timestamp) revert StalenessThresholdExceeded();

//         if (_priceBase <= 0 || _priceQuote <= 0) revert PriceNotValid();
//         return (uint256(_priceBase), uint256(_priceQuote));
//     }
// }
