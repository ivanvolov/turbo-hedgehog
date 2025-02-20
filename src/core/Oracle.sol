// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

contract Oracle is IOracle {
    AggregatorV3Interface internal feedBase;
    AggregatorV3Interface internal feedQuote;

    constructor(address _feedQuote, address _feedBase) {
        feedQuote = AggregatorV3Interface(_feedQuote);
        feedBase = AggregatorV3Interface(_feedBase);
    }

    function price() external view returns (uint256) {
        (, int256 _priceQuote, , , ) = feedQuote.latestRoundData();
        uint8 decimalsQuote = feedQuote.decimals();
        (, int256 _priceBase, , , ) = feedBase.latestRoundData();
        uint8 decimalsBase = feedBase.decimals();

        if (_priceBase < 0 || _priceQuote < 0) revert("O1");

        uint256 priceBase = (uint256(_priceBase) * 1e18) / (10 ** decimalsBase);
        uint256 priceQuote = (uint256(_priceQuote) * 1e18) / (10 ** decimalsQuote);
        return (priceQuote * 1e18) / priceBase;
    }
}
