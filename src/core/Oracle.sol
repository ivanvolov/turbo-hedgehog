// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

contract Oracle is IOracle {
    AggregatorV3Interface internal priceFeed;

    constructor(address feed) {
        priceFeed = AggregatorV3Interface(feed);
    }

    function price() external view returns (uint256) {
        (, int256 _price, , , ) = priceFeed.latestRoundData();
        return uint256(_price) * 1e10;
    }
}
