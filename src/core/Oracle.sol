// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** libraries
import {PRBMath} from "@prb-math/PRBMath.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

contract Oracle is IOracle {
    AggregatorV3Interface internal immutable feedBase;
    AggregatorV3Interface internal immutable feedQuote;
    uint256 public immutable stalenessThresholdQ;
    uint256 public immutable stalenessThresholdB;

    constructor(address _feedQuote, address _feedBase, uint256 _stalenessThresholdQ, uint256 _stalenessThresholdB) {
        feedQuote = AggregatorV3Interface(_feedQuote);
        feedBase = AggregatorV3Interface(_feedBase);
        stalenessThresholdQ = _stalenessThresholdQ;
        stalenessThresholdB = _stalenessThresholdB;
    }

    /// @notice Returns the price as a 1e18 fixed-point number (UD60x18)
    function price() external view returns (uint256 _price) {
        (, int256 _priceQuote, , uint256 updatedAtQuote, ) = feedQuote.latestRoundData();
        uint8 decimalsQuote = feedQuote.decimals();
        (, int256 _priceBase, , uint256 updatedAtBase, ) = feedBase.latestRoundData();
        uint8 decimalsBase = feedBase.decimals();

        require(_priceBase > 0 && _priceQuote > 0, "O1");
        require(updatedAtQuote >= block.timestamp - stalenessThresholdQ, "O2");
        require(updatedAtBase >= block.timestamp - stalenessThresholdB, "O3");

        uint256 SCALE_FACTOR = 18 + decimalsBase - decimalsQuote;
        _price = PRBMath.mulDiv(uint256(_priceQuote), 10 ** SCALE_FACTOR, uint256(_priceBase));
        require(_price > 0, "O4");
    }
}
