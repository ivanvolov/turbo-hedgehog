// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** contracts
import {OracleBase} from "./OracleBase.sol";

// ** libraries
import {WAD} from "../../libraries/ALMMathLib.sol";

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

    IAggV3 public immutable feedBase;
    IAggV3 public immutable feedQuote;
    StalenessThresholds public stalenessThresholds;

    constructor(
        IAggV3 _feedBase,
        IAggV3 _feedQuote,
        bool _isInvertedPool,
        int256 _tokenDecDelta
    ) OracleBase(_isInvertedPool, calcTotalDecDelta(_tokenDecDelta, _feedBase, _feedQuote)) Ownable(msg.sender) {
        feedBase = _feedBase;
        feedQuote = _feedQuote;
    }

    function setStalenessThresholds(uint128 thresholdBase, uint128 thresholdQuote) external onlyOwner {
        stalenessThresholds = StalenessThresholds(thresholdBase, thresholdQuote);
        emit StalenessThresholdsSet(thresholdBase, thresholdQuote);
    }

    function calcTotalDecDelta(int256 _tokenDecDel, IAggV3 _feedBase, IAggV3 _feedQuote) public view returns (int256) {
        int256 feedBDec = address(_feedBase) == address(0) ? int256(0) : int256(int8(_feedBase.decimals()));
        int256 feedQDec = address(_feedQuote) == address(0) ? int256(0) : int256(int8(_feedQuote.decimals()));
        return _tokenDecDel + feedBDec - feedQDec;
    }

    function _fetchAssetsPrices() internal view override returns (uint256, uint256) {
        StalenessThresholds memory thresholds = stalenessThresholds;
        int256 priceBase = _getOraclePrice(feedBase, thresholds.base);
        int256 priceQuote = _getOraclePrice(feedQuote, thresholds.quote);

        if (priceBase <= 0 || priceQuote <= 0) revert PriceNotValid();
        return (uint256(priceBase), uint256(priceQuote));
    }

    function _getOraclePrice(IAggV3 feed, uint256 stalenessThreshold) internal view returns (int256) {
        if (address(feed) == address(0)) return int256(WAD);
        (, int256 price, , uint256 updatedAt, ) = feed.latestRoundData();
        if (updatedAt + stalenessThreshold < block.timestamp) revert StalenessThresholdExceeded();
        return price;
    }
}
