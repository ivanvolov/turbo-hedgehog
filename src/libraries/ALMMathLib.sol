// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** libraries
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

library ALMMathLib {
    using PRBMathUD60x18 for uint256;

    uint256 constant WAD = 1e18;
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
                ? uint256((baseValue * int256(price)) / int256(WAD) + variableValue)
                : uint256(baseValue + (variableValue * int256(WAD)) / int256(price));
    }

    function getVLP(
        uint256 TVL,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage
    ) internal pure returns (uint256) {
        uint256 ratio = uint256(
            (int256(weight) * (int256(longLeverage) - int256(shortLeverage))) / int256(WAD) + int256(shortLeverage)
        );
        return ratio.mul(TVL);
    }

    function getL(uint256 VLP, uint256 price, uint256 priceUpper, uint256 priceLower) internal pure returns (uint256) {
        return VLP.div((2 * WAD).mul(price.sqrt()) - priceLower.sqrt() - price.div(priceUpper.sqrt())) / 1e6;
    }

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

    // --- Helpers --- //
    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return int24(((int256(PRBMathUD60x18.ln(price * WAD)) - int256(41446531673892820000))) / 99995000333297);
    }

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        return getPriceFromSqrtPriceX96(getSqrtPriceAtTick(tick));
    }

    function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return uint256(sqrtPriceX96).pow(2 * WAD).mul(WAD * WAD).div(Q192);
    }

    function getPoolPriceFromOraclePrice(
        uint256 price,
        bool reversedOrder,
        uint8 decimalsDelta
    ) internal pure returns (uint256) {
        uint256 ratio = WAD * (10 ** decimalsDelta); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
        if (reversedOrder) return ratio.div(price);
        return price.div(ratio);
    }

    function getOraclePriceFromPoolPrice(
        uint256 price,
        bool reversedOrder,
        uint8 decimalsDelta
    ) internal pure returns (uint256) {
        uint256 ratio = WAD * (10 ** decimalsDelta); // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
        if (reversedOrder) return ratio.div(price);
        return ratio.mul(price);
    }

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
