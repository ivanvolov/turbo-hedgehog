// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {UD60x18} from "@prb-math/UD60x18.sol";
import {SD59x18, sd} from "@prb-math/SD59x18.sol";
import {mulDiv, mulDiv18 as mul18} from "@prb-math/Common.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title ALM Math Library
/// @notice Library for all math operations used in the ALM hook.
library ALMMathLib {
    uint256 constant WAD = 1e18;
    UD60x18 constant Q96 = UD60x18.wrap(2 ** 96);

    function getLiquidity(
        bool isInvertedPool,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount,
        uint256 multiplier
    ) internal pure returns (uint128) {
        uint256 liquidity = isInvertedPool
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
        return SafeCast.toUint128(mul18(liquidity, multiplier));
    }

    function getSharesToMint(uint256 TVL1, uint256 TVL2, uint256 ts) internal pure returns (uint256) {
        if (TVL1 == 0) return TVL2;
        else return mulDiv(ts, TVL2 - TVL1, TVL1);
    }

    /**
     * @notice Calculates the Total Value Locked (TVL) in the protocol.
     * @param quoteBalance The total amount of quote tokens held by the protocol.
     * @param baseBalance The total amount of base tokens held by the protocol.
     * @param collateralLong The total value of collateral supporting long positions.
     * @param collateralShort The total value of collateral supporting short positions.
     * @param debtLong The total amount of debt held in long positions.
     * @param debtShort The total amount of debt held in short positions.
     * @param price The price of one quote token in base token units, expressed as an integer with 18-decimal precision.
     * @param returnInBase If true, result is denominated in base token, otherwise in quote token.
     * @return The total value locked, denominated in base or quote units.
     */
    function getTVL(
        uint256 quoteBalance,
        uint256 baseBalance,
        uint256 collateralLong,
        uint256 collateralShort,
        uint256 debtLong,
        uint256 debtShort,
        uint256 price,
        bool returnInBase
    ) internal pure returns (uint256) {
        int256 quoteValue = SafeCast.toInt256(quoteBalance + collateralLong) - SafeCast.toInt256(debtShort);
        int256 baseValue = SafeCast.toInt256(collateralShort + baseBalance) - SafeCast.toInt256(debtLong);

        SD59x18 _price = sd(SafeCast.toInt256(price));
        return
            returnInBase
                ? SafeCast.toUint256(sd(quoteValue).mul(_price).unwrap() + baseValue)
                : SafeCast.toUint256(sd(baseValue).div(_price).unwrap() + quoteValue);
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
        longLeverage = mulDiv(currentCL, price, mul18(currentCL, price) - DL);
        shortLeverage = div18(currentCS, currentCS - mul18(DS, price));
    }

    // ** Helpers

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

    function div18(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDiv(x, WAD, y);
    }

    function absSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
