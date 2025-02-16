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
        //console.log("getTVL");
        //console.log("EH %s", EH); // WETH
        //console.log("UH %s", UH); // USDC
        //console.log("CL %s", CL); // WETH
        //console.log("DS %s", DS); // WETH
        //console.log("CS %s", CS); // USDC
        //console.log("DL %s", DL); // USDC
        //console.log("price %s", price);
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
        return VLP.div(uint256(2e18).mul(price.sqrt()) - priceLower.sqrt() - price.div(priceUpper.sqrt())) / 1e6; //TODO: I bet this is not universal
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
        console.log("price Input: %s", int256(price));
        console.log("price Input: %s", lnWad(int256(price)) / 99995000333297);

        return int24(lnWad(int256(price)) / 99995000333297);
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
        // @Notice: 1e12/p, 1e30 is 1e12 with 18 decimals
        // return uint256(1e30).div(price); // TODO: this can change according to decimals and order
        return price.div(uint256(1e30));
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

    function lnWad(int256 x) internal pure returns (int256 r) {
        unchecked {
            require(x > 0, "UNDEFINED");

            // We want to convert x from 10**18 fixed point to 2**96 fixed point.
            // We do this by multiplying by 2**96 / 10**18. But since
            // ln(x * C) = ln(x) + ln(C), we can simply do nothing here
            // and add ln(2**96 / 10**18) at the end.

            // Reduce range of x to (1, 2) * 2**96
            // ln(2^k * x) = k * ln(2) + ln(x)
            int256 k = int256(log2(uint256(x))) - 96;
            x <<= uint256(159 - k);
            x = int256(uint256(x) >> 159);

            // Evaluate using a (8, 8)-term rational approximation.
            // p is made monic, we will multiply by a scale factor later.
            int256 p = x + 3273285459638523848632254066296;
            p = ((p * x) >> 96) + 24828157081833163892658089445524;
            p = ((p * x) >> 96) + 43456485725739037958740375743393;
            p = ((p * x) >> 96) - 11111509109440967052023855526967;
            p = ((p * x) >> 96) - 45023709667254063763336534515857;
            p = ((p * x) >> 96) - 14706773417378608786704636184526;
            p = p * x - (795164235651350426258249787498 << 96);

            // We leave p in 2**192 basis so we don't need to scale it back up for the division.
            // q is monic by convention.
            int256 q = x + 5573035233440673466300451813936;
            q = ((q * x) >> 96) + 71694874799317883764090561454958;
            q = ((q * x) >> 96) + 283447036172924575727196451306956;
            q = ((q * x) >> 96) + 401686690394027663651624208769553;
            q = ((q * x) >> 96) + 204048457590392012362485061816622;
            q = ((q * x) >> 96) + 31853899698501571402653359427138;
            q = ((q * x) >> 96) + 909429971244387300277376558375;
            assembly {
                // Div in assembly because solidity adds a zero check despite the unchecked.
                // The q polynomial is known not to have zeros in the domain.
                // No scaling required because p is already 2**96 too large.
                r := sdiv(p, q)
            }

            // r is in the range (0, 0.125) * 2**96

            // Finalization, we need to:
            // * multiply by the scale factor s = 5.549…
            // * add ln(2**96 / 10**18)
            // * add k * ln(2)
            // * multiply by 10**18 / 2**96 = 5**18 >> 78

            // mul s * 5e18 * 2**96, base is now 5**18 * 2**192
            r *= 1677202110996718588342820967067443963516166;
            // add ln(2) * k * 5e18 * 2**192
            r += 16597577552685614221487285958193947469193820559219878177908093499208371 * k;
            // add ln(2**96 / 10**18) * 5e18 * 2**192
            r += 600920179829731861736702779321621459595472258049074101567377883020018308;
            // base conversion: mul 2**18 / 2**192
            r >>= 174;
        }
    }

    function log2(uint256 x) internal pure returns (uint256 r) {
        assembly {
            r := shl(7, lt(0xffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))

            // For the remaining 32 bits, use a De Bruijn lookup.
            x := shr(r, x)
            x := or(x, shr(1, x))
            x := or(x, shr(2, x))
            x := or(x, shr(4, x))
            x := or(x, shr(8, x))
            x := or(x, shr(16, x))
            r := or(r, byte(shr(251, mul(x, shl(224, 0x07c4acdd))),
                0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f))
        }
    }
}
