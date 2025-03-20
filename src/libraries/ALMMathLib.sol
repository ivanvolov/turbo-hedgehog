// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** libraries
import {UD60x18, ud, unwrap, ln} from "@prb/math/src/UD60x18.sol";
import {SD59x18, convert, convert} from "@prb/math/src/SD59x18.sol";
import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

library ALMMathLib {
    using PRBMathUD60x18 for uint256;

    uint256 constant Q96 = 2 ** 96;
    uint256 constant Q192 = 2 ** 192;

    function sqrtPriceNextX96OneForZeroIn(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = uint160((amount1 * Q96) / liquidity);
        return sqrtPriceCurrentX96 + sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96ZeroForOneOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = uint160((amount1 * Q96) / liquidity);
        return sqrtPriceCurrentX96 - sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96OneForZeroOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint160) {
        return
            uint160(
                uint256(liquidity).mul(uint256(sqrtPriceCurrentX96)).div(
                    uint256(liquidity) - amount0.mul(uint256(sqrtPriceCurrentX96)).div(Q96)
                )
            );
    }

    // function sqrtPriceNextX96OneForZeroOut(
    //     uint160 sqrtPriceCurrentX96,
    //     uint128 liquidity,
    //     uint256 amount0
    // ) internal pure returns (uint160) {
    //     return
    //         uint160(
    //             unwrap(
    //                 ud(liquidity).mul(ud(sqrtPriceCurrentX96)).div(
    //                     ud(liquidity) - ud(amount0).mul(ud(sqrtPriceCurrentX96)).div(ud(Q96))
    //                 )
    //             )
    //         );
    // }

    function sqrtPriceNextX96ZeroForOneIn(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint160) {
        return
            uint160(
                uint256(liquidity).mul(uint256(sqrtPriceCurrentX96)).div(
                    uint256(liquidity) + amount0.mul(uint256(sqrtPriceCurrentX96)).div(Q96)
                )
            );
    }

    // function sqrtPriceNextX96ZeroForOneIn(
    //     uint160 sqrtPriceCurrentX96,
    //     uint128 liquidity,
    //     uint256 amount0
    // ) internal pure returns (uint160) {
    //     return
    //         uint160(
    //             unwrap(
    //                 ud(liquidity).mul(ud(sqrtPriceCurrentX96)).div(
    //                     ud(liquidity) + ud(amount0).mul(ud(sqrtPriceCurrentX96)).div(ud(Q96))
    //                 )
    //             )
    //         );
    // }

    function getSwapAmount0(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceNextX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return (LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity));
    }

    function getSwapAmount1(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceNextX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return (LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity));
    }

    function getSharesToMint(uint256 TVL1, uint256 TVL2, uint256 ts) internal pure returns (uint256) {
        if (TVL1 == 0) return TVL2;
        else return (ts.mul(TVL2 - TVL1)).div(TVL1);
    }

    function getTVL(
        uint256 EH,
        uint256 UH,
        uint256 CL,
        uint256 DS,
        uint256 CS,
        uint256 DL,
        uint256 price,
        bool isStable
    ) internal pure returns (uint256) {
        int256 baseValue = int256(EH) + int256(CL) - int256(DS);
        int256 variableValue = int256(CS) + int256(UH) - int256(DL);

        return
            isStable
                ? uint256((baseValue * int256(price)) / 1e18 + variableValue)
                : uint256(baseValue + (variableValue * 1e18) / int256(price));
    }

    function getVLP(
        uint256 TVL,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage
    ) internal pure returns (uint256) {
        uint256 ratio = uint256(
            (int256(weight) * (int256(longLeverage) - int256(shortLeverage))) / 1e18 + int256(shortLeverage)
        );
        return ratio.mul(TVL);
    }

    function getL(uint256 VLP, uint256 price, uint256 priceUpper, uint256 priceLower) internal pure returns (uint256) {
        return VLP.div(uint256(2e18).mul(price.sqrt()) - priceLower.sqrt() - price.div(priceUpper.sqrt())) / 1e6;
    }

    // function getSharesToMint(uint256 TVL1, uint256 TVL2, uint256 ts) internal pure returns (uint256) {
    //     if (TVL1 == 0) return TVL2;
    //     else return unwrap((ud(ts).mul(ud(TVL2 - TVL1))).div(ud(TVL1)));
    // }

    // function getTVL(
    //     uint256 EH,
    //     uint256 UH,
    //     uint256 CL,
    //     uint256 DS,
    //     uint256 CS,
    //     uint256 DL,
    //     uint256 price,
    //     bool isStable
    // ) internal pure returns (uint256) {
    //     SD59x18 baseValue = convert(int256(EH) + int256(CL) - int256(DS));
    //     SD59x18 variableValue = convert(int256(CS) + int256(UH) - int256(DL));

    //     return
    //         isStable
    //             ? uint256(convert((baseValue.mul(convert(int256(price))) + variableValue)))
    //             : uint256(convert((baseValue + variableValue).div(convert(int256(price)))));
    // }

    // function getVLP(
    //     uint256 TVL,
    //     uint256 weight,
    //     uint256 longLeverage,
    //     uint256 shortLeverage
    // ) internal pure returns (uint256) {
    //     UD60x18 ratio = ud(
    //         uint256((int256(weight) * (int256(longLeverage) - int256(shortLeverage))) / 1e18 + int256(shortLeverage))
    //     );
    //     return unwrap(ratio.mul(ud(TVL)));
    // }

    // function getL(uint256 VLP, uint256 price, uint256 priceUpper, uint256 priceLower) internal pure returns (uint256) {
    //     return
    //         unwrap(
    //             ud(VLP).div(
    //                 ud(2e18).mul(ud(price).sqrt()) - ud(priceLower).sqrt() - ud(price).div(ud(priceUpper).sqrt())
    //             )
    //         ) / 1e6;
    // }

    function getUserAmounts(
        uint256 totalSupply,
        uint256 sharesOut,
        uint256 collateralLong,
        uint256 collateralShort,
        uint256 debtLong,
        uint256 debtShort
    ) internal pure returns (uint256, uint256, uint256, uint256) {
        uint256 ratio = sharesOut.div(totalSupply);

        return (collateralLong.mul(ratio), collateralShort.mul(ratio), debtLong.mul(ratio), debtShort.mul(ratio));
    }

    // function getUserAmounts(
    //     uint256 totalSupply,
    //     uint256 sharesOut,
    //     uint256 collateralLong,
    //     uint256 collateralShort,
    //     uint256 debtLong,
    //     uint256 debtShort
    // ) internal pure returns (uint256, uint256, uint256, uint256) {
    //     UD60x18 ratio = ud(sharesOut).div(ud(totalSupply));

    //     return (
    //         unwrap(ud(collateralLong).mul(ratio)),
    //         unwrap(ud(collateralShort).mul(ratio)),
    //         unwrap(ud(debtLong).mul(ratio)),
    //         unwrap(ud(debtShort).mul(ratio))
    //     );
    // }

    // --- Helpers --- //
    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return int24(((int256(PRBMathUD60x18.ln(price * 1e18)) - int256(41446531673892820000))) / 99995000333297);
    }

    // function getTickFromPrice(uint256 price) internal pure returns (int24) {
    //     return int24(((int256(unwrap(ln(ud(price * 1e18)))) - int256(41446531673892820000))) / 99995000333297);
    // }

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        return getPriceFromSqrtPriceX96(getSqrtPriceAtTick(tick));
    }

    function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return (uint256(sqrtPriceX96)).pow(uint256(2e18)).mul(1e36).div(Q192);
    }

    // function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
    //     return unwrap(ud(sqrtPriceX96).pow(ud(2e18)).mul(ud(1e36)).div(ud(Q192)));
    // }

    function getPoolPriceFromOraclePrice(
        uint256 price,
        bool reversedOrder,
        uint8 decimalsDelta
    ) internal pure returns (uint256) {
        uint256 ratio = 1e18 * (10 ** decimalsDelta); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
        if (reversedOrder) return ratio.div(price);
        return price.div(ratio);
    }

    // function getPoolPriceFromOraclePrice(
    //     uint256 price,
    //     bool reversedOrder,
    //     uint8 decimalsDelta
    // ) internal pure returns (uint256) {
    //     UD60x18 ratio = ud(1e18 * (10 ** decimalsDelta)); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
    //     if (reversedOrder) return unwrap(ratio.div(ud(price)));
    //     return unwrap(ud(price).div(ratio));
    // }

    function getOraclePriceFromPoolPrice(
        uint256 price,
        bool reversedOrder,
        uint8 decimalsDelta
    ) internal pure returns (uint256) {
        uint256 ratio = 1e18 * (10 ** decimalsDelta); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
        if (reversedOrder) return ratio.div(price);
        return ratio.mul(price);
    }

    // function getOraclePriceFromPoolPrice(
    //     uint256 price,
    //     bool reversedOrder,
    //     uint8 decimalsDelta
    // ) internal pure returns (uint256) {
    //     UD60x18 ratio = ud(1e18 * (10 ** decimalsDelta)); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
    //     if (reversedOrder) return unwrap(ratio.div(ud(price)));
    //     return unwrap(ratio.mul(ud(price)));
    // }

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}
