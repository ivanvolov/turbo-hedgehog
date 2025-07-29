// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** libraries
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ABDKMath64x64} from "@test/libraries/math/ABDKMath64x64.sol";
import {PRBMathUD60x18, PRBMath} from "@test/libraries/math/PRBMathUD60x18.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

library TestLib {
    using PRBMathUD60x18 for uint256;

    // ** Uniswap math

    uint256 constant sqrt_price_10per = 1048808848170150000; // (sqrt(1.1) or max 10% price change
    uint256 constant sqrt_price_1per = 1004987562112090000; // (sqrt(1.01) or max 1% price change
    uint256 constant ONE_PERCENT_AND_ONE_BPS = 101e16; // 1.01%

    uint256 constant WAD = 1e18;
    uint256 constant Q192 = 2 ** 192;

    function getOraclePriceFromPoolPrice(
        uint256 price,
        bool reversedOrder,
        int8 decimalsDelta
    ) internal pure returns (uint256) {
        if (decimalsDelta < 0) {
            uint256 ratio = WAD * (10 ** uint8(-decimalsDelta));
            if (reversedOrder) return ratio.div(price);
            else return price.mul(ratio);
        } else {
            uint256 ratio = WAD * (10 ** uint8(decimalsDelta));
            if (reversedOrder) return WAD.div(price.mul(ratio));
            else return price.div(ratio);
        }
    }

    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return ALMMathLib.getTickFromSqrtPriceX96(ALMMathLib.getSqrtPriceX96FromPrice(price));
    }

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        return getPriceFromSqrtPriceX96(ALMMathLib.getSqrtPriceX96FromTick(tick));
    }

    function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return PRBMath.mulDiv(uint256(sqrtPriceX96).mul(sqrtPriceX96), WAD * WAD, Q192);
    }

    function nearestUsableTick(int24 tick_, uint24 tickSpacing) internal pure returns (int24 result) {
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
}
