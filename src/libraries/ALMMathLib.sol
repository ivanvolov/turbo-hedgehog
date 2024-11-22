// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";

library ALMMathLib {
    using PRBMathUD60x18 for uint256;

    function sqrtPriceNextX96OneForZeroIn(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = toUint160((amount1 * 2 ** 96) / liquidity);
        return sqrtPriceCurrentX96 + sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96ZeroForOneOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = toUint160((amount1 * 2 ** 96) / liquidity);
        return sqrtPriceCurrentX96 - sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96OneForZeroOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint160) {
        return
            toUint160(
                uint256(liquidity).mul(uint256(sqrtPriceCurrentX96)).div(
                    uint256(liquidity) -
                        amount0.mul(uint256(sqrtPriceCurrentX96)).div(2 ** 96)
                )
            );
    }

    function sqrtPriceNextX96ZeroForOneIn(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint160) {
        return
            toUint160(
                uint256(liquidity).mul(uint256(sqrtPriceCurrentX96)).div(
                    uint256(liquidity) +
                        amount0.mul(uint256(sqrtPriceCurrentX96)).div(2 ** 96)
                )
            );
    }

    function getSwapAmount0(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceNextX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return (
            LiquidityAmounts.getAmount0ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            )
        );
    }

    function getSwapAmount1(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceNextX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return (
            LiquidityAmounts.getAmount1ForLiquidity(
                sqrtPriceNextX96,
                sqrtPriceCurrentX96,
                liquidity
            )
        );
    }

    function getLiquidityFromAmount1SqrtPriceX96(
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount1(
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                amount1
            );
    }

    function getAmountsFromLiquiditySqrtPriceX96(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceUpperX96,
        uint160 sqrtPriceLowerX96,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceCurrentX96,
                sqrtPriceUpperX96,
                sqrtPriceLowerX96,
                liquidity
            );
    }

    function calculateSwapFee(
        int256 RV7,
        int256 RV30
    ) internal pure returns (uint256) {
        int256 F0 = 3000000000000000; // 0.003
        int256 alpha = 2049000000000000000; // 2.049
        int256 minFee = 500000000000000; //0.05%
        int256 maxFess = 5000000000000000; //0.5%

        int256 R = (alpha * (((RV7 * 1e18) / RV30) - 1e18)) / 1e18;
        return uint256(max(minFee, min(maxFess, (F0 * (1e18 + R)) / 1e18)));
    }

    function getPriceFromSqrtPriceX96(
        uint160 sqrtPriceX96
    ) internal pure returns (uint256) {
        //const = 2^192
        uint256 price = uint256(sqrtPriceX96).pow(uint256(2e18)).mul(1e36).div(
            6277101735386680763835789423207666416102355444464034512896
        );
        return uint256(1e30).div(price);
    }

    function getWithdrawAmount(
        uint256 shares,
        uint256 totalSupply,
        uint256 amount
    ) internal pure returns (uint256) {
        uint256 ratio = shares.div(totalSupply);
        return amount.mul(ratio);
    }

    // --- Helpers ---

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function getTickFromSqrtPrice(
        uint160 sqrtPriceX96
    ) internal pure returns (int24) {
        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function toInt24(int256 value) internal pure returns (int24) {
        require(value >= type(int24).min && value <= type(int24).max, "MH1");
        return int24(value);
    }

    function toUint160(uint256 value) internal pure returns (uint160) {
        require(value <= type(uint160).max, "MH2");
        return uint160(value);
    }

    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
