// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** libraries
import {TestLib} from "@test/libraries/TestLib.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";

/// @title Test Oracle
/// @notice Contract for simulation testing of an Oracle.
contract TestOracle is IOracle {
    function getPrices(
        uint256 priceBase,
        uint256 priceQuote,
        int256 totalDecDel,
        bool isInvertedPool
    ) external pure returns (uint256, uint160) {
        return TestLib.newOracleGetPrices(priceBase, priceQuote, totalDecDel, isInvertedPool);
    }

    function poolPrice() external view returns (uint256, uint160) {}

    function price() external view returns (uint256) {}
}
