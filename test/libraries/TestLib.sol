// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AggregatorV3Interface as IAggV3} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

// ** libraries
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ABDKMath64x64} from "@test/libraries/math/ABDKMath64x64.sol";
import {PRBMathUD60x18, PRBMath} from "@test/libraries/math/PRBMathUD60x18.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {UD60x18, ud} from "@prb-math/UD60x18.sol";
import {mulDiv, mulDiv18 as mul18, sqrt} from "@prb-math/Common.sol";

library TestLib {
    using PRBMathUD60x18 for uint256;

    IAggV3 constant ZERO_FEED = IAggV3(address(0));
    IWETH9 constant ZERO_WETH9 = IWETH9(address(0));

    // ** Uniswap math

    uint256 constant sqrt_price_10per = 1048808848170150000; // (sqrt(1.1) or max 10% price change
    uint256 constant sqrt_price_1per = 1004987562112090000; // (sqrt(1.01) or max 1% price change
    uint256 constant ONE_PERCENT_AND_ONE_BPS = 101e16; // 1.01%

    uint256 constant WAD = 1e18;
    uint256 constant Q192 = 2 ** 192;
    UD60x18 constant Q96 = UD60x18.wrap(2 ** 96);

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

    function getSqrtPriceX96FromPrice(uint256 price) internal pure returns (uint160) {
        return SafeCast.toUint160(ud(price).sqrt().mul(Q96).unwrap());
    }

    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return ALMMathLib.getTickFromSqrtPriceX96(getSqrtPriceX96FromPrice(price));
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

    function newOracleGetPrices(
        uint256 _priceBase,
        uint256 _priceQuote,
        int256 _totalDecimalsDelta,
        bool _isInvertedPool
    ) public pure returns (uint256 _price, uint160 _sqrtPriceX96) {
        if (_totalDecimalsDelta < -18) revert("DecimalsDeltaNotValid");
        uint256 scaleFactor = 10 ** SafeCast.toUint256(_totalDecimalsDelta + 18);
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);

        if (_totalDecimalsDelta < 0) {
            _priceBase = _priceBase * 10 ** uint256(-_totalDecimalsDelta);
        } else if (_totalDecimalsDelta > 0) {
            _priceQuote = _priceQuote * 10 ** uint256(_totalDecimalsDelta);
        }
        bool invert = _priceBase <= _priceQuote;
        (uint256 lowP, uint256 highP) = invert ? (_priceBase, _priceQuote) : (_priceQuote, _priceBase);
        uint256 r = mulDiv(lowP, type(uint256).max, highP);
        r = sqrt(r);
        if (invert != _isInvertedPool) r = type(uint256).max / r;
        r = r >> 32;
        _sqrtPriceX96 = SafeCast.toUint160(r);
        // We don't need constraints for testing.
        // require(_price != 0, "PriceZero");
        // require(_sqrtPriceX96 != 0, "SqrtPriceZero");
    }

    function oldOracleGetPrices(
        uint256 _priceBase,
        uint256 _priceQuote,
        int256 _totalDecimalsDelta,
        bool _isInvertedPool
    ) public pure returns (uint256 _price, uint160 _sqrtPriceX96) {
        uint256 scaleFactor = 10 ** uint256(_totalDecimalsDelta + 18);
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);
        uint256 __price = _isInvertedPool ? ALMMathLib.div18(ALMMathLib.WAD, _price) : _price;
        _sqrtPriceX96 = SafeCast.toUint160(ud(__price).sqrt().mul(ud(2 ** 96)).unwrap());
    }

    function newOracleGetPrice(
        uint256 _priceBase,
        uint256 _priceQuote,
        int256 _totalDecimalsDelta
    ) public pure returns (uint256 _price) {
        uint256 scaleFactor = 10 ** uint256(_totalDecimalsDelta + 18);
        _price = mulDiv(_priceQuote, scaleFactor, _priceBase);
    }
}
