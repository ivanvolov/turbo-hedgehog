// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// ** libraries
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ABDKMath64x64} from "@test/libraries/ABDKMath64x64.sol";

library TestMathLib {
    function nearestUsableTick(int24 tick_, uint24 tickSpacing) public pure returns (int24 result) {
        result = int24(divRound(int128(tick_), int128(int24(tickSpacing)))) * int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }

    function divRound(int128 x, int128 y) internal pure returns (int128 result) {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        // Check if remainder is greater than 0.5
        if (quot % 2 ** 64 >= 0x8000000000000000) {
            result += 1;
        }
    }

    function getTickSpacingFromFee(uint24 fee) public pure returns (int24) {
        return int24((fee / 100) * 2);
    }
}
