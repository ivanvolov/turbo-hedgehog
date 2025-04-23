// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {PRBMath} from "@prb-math/PRBMath.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** interfaces
import {IOracle} from "../interfaces/IOracle.sol";

contract Oracle is IOracle {
    AggregatorV3Interface internal immutable feedBase;
    AggregatorV3Interface internal immutable feedQuote;
    uint256 public immutable stalenessThresholdQ;
    uint256 public immutable stalenessThresholdB;

    constructor(
        AggregatorV3Interface _feedQuote,
        AggregatorV3Interface _feedBase,
        uint256 _stalenessThresholdQ,
        uint256 _stalenessThresholdB
    ) {
        feedQuote = _feedQuote;
        feedBase = _feedBase;
        stalenessThresholdQ = _stalenessThresholdQ;
        stalenessThresholdB = _stalenessThresholdB;
    }

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function price() external view returns (uint256 _price) {
        (, int256 _priceQuote, , uint256 updatedAtQuote, ) = feedQuote.latestRoundData();
        require(block.timestamp - updatedAtQuote <= stalenessThresholdQ, "O1");

        (, int256 _priceBase, , uint256 updatedAtBase, ) = feedBase.latestRoundData();
        require(block.timestamp - updatedAtBase <= stalenessThresholdB, "O2");

        require(_priceBase > 0 && _priceQuote > 0, "O3");

        uint8 decimalsQuote = feedQuote.decimals();
        uint8 decimalsBase = feedBase.decimals();
        uint256 scaleFactor = 18 + decimalsBase - decimalsQuote;
        _price = PRBMath.mulDiv(uint256(_priceQuote), 10 ** scaleFactor, uint256(_priceBase));
        require(_price > 0, "O4");
    }
}
