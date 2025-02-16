// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

contract Oracle is IOracle {
    AggregatorV3Interface internal feedBased;
    AggregatorV3Interface internal feedTarget;

    constructor(address _feedTarget, address _feedBased) {
        feedTarget = AggregatorV3Interface(_feedTarget);
        feedBased = AggregatorV3Interface(_feedBased);
    }

    function price() external view returns (uint256) {
        (, int256 _priceTarget, , , ) = feedTarget.latestRoundData();
        uint8 decimalsTarget = feedTarget.decimals();
        (, int256 _priceBased, , , ) = feedBased.latestRoundData();
        uint8 decimalsBased = feedBased.decimals();

        if (_priceBased < 0 || _priceTarget < 0) revert("O1");

        uint256 priceBased = (uint256(_priceBased) * 1e18) / (10 ** decimalsBased);
        uint256 priceTarget = (uint256(_priceTarget) * 1e18) / (10 ** decimalsTarget);
        return (priceTarget * 1e18) / priceBased;
    }
}
