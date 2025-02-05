// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** libraries
import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

//TODO: refactor. Remove unused functions
library ALMMathLib {
    using PRBMathUD60x18 for uint256;

    function sqrtPriceNextX96OneForZeroIn(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = uint160((amount1 * 2 ** 96) / liquidity);
        return sqrtPriceCurrentX96 + sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96ZeroForOneOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = uint160((amount1 * 2 ** 96) / liquidity);
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
                    uint256(liquidity) - amount0.mul(uint256(sqrtPriceCurrentX96)).div(2 ** 96)
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
                    uint256(liquidity) + amount0.mul(uint256(sqrtPriceCurrentX96)).div(2 ** 96)
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

    function calculateSwapFee(int256 RV7, int256 RV30) internal pure returns (uint256) {
        int256 F0 = 0; // 0.003
        int256 alpha = 0; // 2.049
        int256 minFee = 0; //0.05%
        int256 maxFess = 0; //0.5%

        int256 R = (alpha * (((RV7 * 1e18) / RV30) - 1e18)) / 1e18;
        return uint256(SignedMath.max(minFee, SignedMath.min(maxFess, (F0 * (1e18 + R)) / 1e18)));
    }

    function getWithdrawAmount(uint256 shares, uint256 totalSupply, uint256 amount) internal pure returns (uint256) {
        uint256 ratio = shares.div(totalSupply);
        return amount.mul(ratio);
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
        uint256 price
    ) internal pure returns (uint256) {
        // console.log("getTVL");
        // console.log("EH %s", EH); // WETH
        // console.log("UH %s", UH); // USDC
        // console.log("CL %s", CL); // WETH
        // console.log("DS %s", DS); // WETH
        // console.log("CS %s", CS); // USDC
        // console.log("DL %s", DL); // USDC
        // console.log("price %s", price);
        // console.log("A", int256(EH) + int256(CL) - int256(DS));
        // console.log("B", ((int256(CS) + int256(UH) - int256(DL)) * int256(price)) / 1e18);
        return
            uint256(
                int256(EH) + int256(CL) - int256(DS) + (((int256(CS) + int256(UH) - int256(DL)) * 1e18) / int256(price))
            );
    }

    function getTVLStable(
        uint256 EH,
        uint256 UH,
        uint256 CL,
        uint256 DS,
        uint256 CS,
        uint256 DL,
        uint256 price
    ) internal pure returns (uint256) {
        return
            uint256(
                ((int256(EH) + int256(CL) - int256(DS)) * int256(price)) / 1e18 + int256(CS) + int256(UH) - int256(DL)
            );
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
        return VLP.div(uint256(2 * 1e18).mul(price.sqrt()) - priceLower.sqrt() - price.div(priceUpper.sqrt())) / 1e6;
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
        // console.log("ratio %s", ratio);
        return (collateralLong.mul(ratio), collateralShort.mul(ratio), debtLong.mul(ratio), debtShort.mul(ratio));
    }

    // --- Helpers --- //
    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        console.log("price Input %s", price);
        return int24(((int256(PRBMathUD60x18.ln(price * 1e18)) - int256(41446531673892820000))) / 99995000333297);
    }

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        return getPriceFromSqrtPriceX96(getSqrtPriceAtTick(tick));
    }

    function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        uint256 const = 6277101735386680763835789423207666416102355444464034512896; // const = 2^192
        return (uint256(sqrtPriceX96)).pow(uint256(2e18)).mul(1e36).div(const);
        // TODO: witch is better test: (sqrtPriceX96.div(2 ** 96)).mul(sqrtPriceX96.div(2 ** 96));
    }

    function reversePrice(uint256 price) internal pure returns (uint256) {
        return uint256(1e30).div(price); // TODO: this can change according to decimals and order
    }

    function getSqrtPriceAtTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function getTickFromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (int24) {
        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function abs(int256 n) internal pure returns (uint256) {
        return SignedMath.abs(n);
    }
}
