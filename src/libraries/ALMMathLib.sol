// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** libraries
import {PRBMathUD60x18, PRBMath} from "@prb-math/PRBMathUD60x18.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

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
        uint160 sqrtPriceDeltaX96 = SafeCast.toUint160(PRBMath.mulDiv(amount1, Q96, liquidity));
        return sqrtPriceCurrentX96 + sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96ZeroForOneOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount1
    ) internal pure returns (uint160) {
        uint160 sqrtPriceDeltaX96 = SafeCast.toUint160(PRBMath.mulDiv(amount1, Q96, liquidity));
        return sqrtPriceCurrentX96 - sqrtPriceDeltaX96;
    }

    function sqrtPriceNextX96OneForZeroOut(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint160) {
        return
            SafeCast.toUint160(
                PRBMath.mulDiv(
                    liquidity,
                    sqrtPriceCurrentX96,
                    liquidity - PRBMath.mulDiv(amount0, sqrtPriceCurrentX96, Q96)
                )
            );
    }

    function sqrtPriceNextX96ZeroForOneIn(
        uint160 sqrtPriceCurrentX96,
        uint128 liquidity,
        uint256 amount0
    ) internal pure returns (uint160) {
        return
            SafeCast.toUint160(
                PRBMath.mulDiv(
                    liquidity,
                    sqrtPriceCurrentX96,
                    liquidity + PRBMath.mulDiv(amount0, sqrtPriceCurrentX96, Q96)
                )
            );
    }

    function getSwapAmount0(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceNextX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return LiquidityAmounts.getAmount0ForLiquidity(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity);
    }

    function getSwapAmount1(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceNextX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        return LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity);
    }

    function getSharesToMint(uint256 TVL1, uint256 TVL2, uint256 ts) internal pure returns (uint256) {
        if (TVL1 == 0) return TVL2;
        else return PRBMath.mulDiv(ts, TVL2 - TVL1, TVL1);
    }

    /**
     * @notice Calculates the Total Value Locked in a protocol.
     * @param quoteBalance The total amount of quote tokens held by the protocol.
     * @param baseBalance The total amount of base tokens held by the protocol.
     * @param collateralLong The total value of collateral supporting long positions.
     * @param collateralShort The total value of collateral supporting short positions.
     * @param debtLong The total amount of debt held in long positions.
     * @param debtShort The total amount of debt held in short positions.
     */
    function getTVL(
        uint256 quoteBalance,
        uint256 baseBalance,
        uint256 collateralLong,
        uint256 collateralShort,
        uint256 debtLong,
        uint256 debtShort,
        uint256 price,
        bool isStable
    ) internal pure returns (uint256) {
        int256 baseValue = SafeCast.toInt256(quoteBalance + collateralLong) - SafeCast.toInt256(debtShort);
        int256 variableValue = SafeCast.toInt256(collateralShort + baseBalance) - SafeCast.toInt256(debtLong);

        return
            isStable
                ? SafeCast.toUint256(mulDiv(baseValue, price, WAD) + variableValue)
                : SafeCast.toUint256(mulDiv(variableValue, WAD, price) + baseValue);
    }

    function getVirtualValue(
        uint256 value,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage
    ) internal pure returns (uint256) {
        return (weight.mul(longLeverage - shortLeverage) + shortLeverage).mul(value);
    }

    function getVirtualLiquidity(
        uint256 virtualValue,
        uint256 price,
        uint256 priceUpper,
        uint256 priceLower
    ) internal pure returns (uint256) {
        return virtualValue.div((2 * WAD).mul(price.sqrt()) - priceLower.sqrt() - price.div(priceUpper.sqrt())) / 1e6;
    }

    function getUserAmounts(
        uint256 totalSupply,
        uint256 sharesOut,
        uint256 collateralLong,
        uint256 collateralShort,
        uint256 debtLong,
        uint256 debtShort
    ) internal pure returns (uint256, uint256, uint256, uint256) {
        return (
            PRBMath.mulDiv(collateralLong, sharesOut, totalSupply),
            PRBMath.mulDiv(collateralShort, sharesOut, totalSupply),
            PRBMath.mulDiv(debtLong, sharesOut, totalSupply),
            PRBMath.mulDiv(debtShort, sharesOut, totalSupply)
        );
    }

    // ** Helpers
    function getTickFromPrice(uint256 price) internal pure returns (int24) {
        return TickMath.getTickAtSqrtPrice(uint160(PRBMath.mulDiv(PRBMathUD60x18.sqrt(price), Q96, WAD)));
    }

    function getPriceFromTick(int24 tick) internal pure returns (uint256) {
        return getPriceFromSqrtPriceX96(getSqrtPriceAtTick(tick));
    }

    function getPriceFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return PRBMath.mulDiv(uint256(sqrtPriceX96).mul(sqrtPriceX96), WAD * WAD, Q192);
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

    // ** Math functions

    /// @notice Calculates floor(x*y÷denominator) with full precision for signed x and unsigned y and denominator.
    function mulDiv(int256 a, uint256 b, uint256 denominator) internal pure returns (int256) {
        uint256 result = PRBMath.mulDiv(SignedMath.abs(a), b, denominator);
        return a < 0 ? -SafeCast.toInt256(result) : SafeCast.toInt256(result);
    }

    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
