// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";

interface IOracleTest is IOracle {
    function feedBase() external view returns (AggregatorV3Interface);

    function feedQuote() external view returns (AggregatorV3Interface);
}

interface IChronicleSelfKisser {
    function selfKiss(address oracle, address who) external;
}
