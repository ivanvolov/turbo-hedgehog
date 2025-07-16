// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** libraries
import {UD60x18, ud} from "@prb-math/UD60x18.sol";
import {mulDiv} from "@prb-math/Common.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@src/libraries/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @title ALM Math Library
/// @notice Library for all math operations used in the ALM hook.
library ALMMathLib {
    uint256 constant WAD = 1e18;
    UD60x18 constant udWAD = UD60x18.wrap(1e18);
    uint256 constant Q96 = 2 ** 96;

    function getLiquidity(
        bool isInvertedPool,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount,
        uint256 multiplier
    ) internal pure returns (uint128) {
        uint256 _liquidity = isInvertedPool
            ? LiquidityAmounts.getLiquidityForAmount1(
                getSqrtPriceX96FromTick(tickLower),
                getSqrtPriceX96FromTick(tickUpper),
                amount
            )
            : LiquidityAmounts.getLiquidityForAmount0(
                getSqrtPriceX96FromTick(tickLower),
                getSqrtPriceX96FromTick(tickUpper),
                amount
            );
        return SafeCast.toUint128(mulDiv(_liquidity, multiplier, WAD));
    }

    function getSharesToMint(uint256 TVL1, uint256 TVL2, uint256 ts) internal pure returns (uint256) {
        if (TVL1 == 0) return TVL2;
        else return mulDiv(ts, TVL2 - TVL1, TVL1);
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
                ? SafeCast.toUint256(_mulDiv(baseValue, price, WAD) + variableValue)
                : SafeCast.toUint256(_mulDiv(variableValue, WAD, price) + baseValue);
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
            mulDiv(collateralLong, sharesOut, totalSupply),
            mulDiv(collateralShort, sharesOut, totalSupply),
            mulDiv(debtLong, sharesOut, totalSupply),
            mulDiv(debtShort, sharesOut, totalSupply)
        );
    }

    function getLeverages(
        uint256 price,
        uint256 currentCL,
        uint256 currentCS,
        uint256 DL,
        uint256 DS
    ) internal pure returns (uint256 longLeverage, uint256 shortLeverage) {
        longLeverage = mulDiv(currentCL, price, ud(currentCL).mul(ud(price)).unwrap() - DL);
        shortLeverage = ud(currentCS).div(ud(currentCS) - ud(DS).mul(ud(price))).unwrap();
    }

    // ** Helpers

    function getSqrtPriceX96FromPrice(uint256 price) internal pure returns (uint160) {
        return SafeCast.toUint160(mulDiv(ud(price).sqrt().unwrap(), Q96, WAD));
    }

    function getSqrtPriceX96FromTick(int24 tick) internal pure returns (uint160) {
        return TickMath.getSqrtPriceAtTick(tick);
    }

    function getTickFromSqrtPriceX96(uint160 sqrtPriceX96) internal pure returns (int24) {
        return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
    }

    /// @notice Aligns a given tick with the tickSpacing of the pool.
    ///         Always rounds down.
    /// @param tick The tick to align
    /// @param tickSpacing The tick spacing of the pool
    function alignComputedTickWithTickSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        if (tick < 0) {
            // If the tick is negative, we round up (negatively) the negative result to round down
            return ((tick - tickSpacing + 1) / tickSpacing) * tickSpacing;
        } else {
            // Else if positive, we simply round down
            return (tick / tickSpacing) * tickSpacing;
        }
    }

    // ** Math functions

    /// @notice Calculates floor(x*y÷denominator) with full precision for signed x and unsigned y and denominator.
    function _mulDiv(int256 a, uint256 b, uint256 denominator) internal pure returns (int256) {
        uint256 result = mulDiv(SignedMath.abs(a), b, denominator);
        return a < 0 ? -SafeCast.toInt256(result) : SafeCast.toInt256(result);
    }

    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
