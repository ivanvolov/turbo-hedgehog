// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";

// ** contracts
import {TestBaseUtils} from "@test/core/common/TestBaseUtils.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {LiquidityAmounts} from "v4-core-test/utils/LiquidityAmounts.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

abstract contract TestBaseAsserts is TestBaseUtils {
    uint256 public ASSERT_EQ_PS_THRESHOLD_CL;
    uint256 public ASSERT_EQ_PS_THRESHOLD_CS;
    uint256 public ASSERT_EQ_PS_THRESHOLD_DL;
    uint256 public ASSERT_EQ_PS_THRESHOLD_DS;
    uint256 public ASSERT_EQ_BALANCE_Q_THRESHOLD = 2;
    uint256 public ASSERT_EQ_BALANCE_B_THRESHOLD = 15;

    mapping(address => uint256) public balanceB;
    mapping(address => uint256) public balanceQ;

    function saveBalance(address owner) public {
        balanceB[owner] = BASE.balanceOf(owner);
        balanceQ[owner] = QUOTE.balanceOf(owner);
    }

    function assertBalanceNotChanged(address owner, uint256 precision) public view {
        assertApproxEqAbs(BASE.balanceOf(owner), balanceB[owner], precision, "BASE balance");
        assertApproxEqAbs(QUOTE.balanceOf(owner), balanceQ[owner], precision, "QUOTE balance");
    }

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0);
    }

    function assertEqBalanceState(address owner, uint256 _balanceQ, uint256 _balanceB) public view {
        try this._assertEqBalanceState(owner, _balanceQ, _balanceB) {
            // Intentionally empty
        } catch {
            console.log("Error: QUOTE Balance", QUOTE.balanceOf(owner));
            console.log("Error: BASE Balance", BASE.balanceOf(owner));
            _assertEqBalanceState(owner, _balanceQ, _balanceB); // This is to throw the error
        }
    }

    function _assertEqBalanceState(address owner, uint256 _balanceQ, uint256 _balanceB) public view {
        assertApproxEqAbs(
            QUOTE.balanceOf(owner),
            _balanceQ,
            ASSERT_EQ_BALANCE_Q_THRESHOLD,
            string.concat("Balance ", quoteName, " not equal")
        );
        assertApproxEqAbs(
            BASE.balanceOf(owner),
            _balanceB,
            ASSERT_EQ_BALANCE_B_THRESHOLD,
            string.concat("Balance ", baseName, " not equal")
        );
    }

    function assertTicks(int24 lower, int24 upper) internal view {
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        assertEq(tickLower, lower);
        assertEq(tickUpper, upper);
    }

    function assertEqHookPositionState(
        uint256 preRebalanceTVL,
        uint256 weight,
        uint256 longLeverage,
        uint256 shortLeverage,
        uint256 slippage
    ) public view {
        ILendingAdapter _lendingAdapter = ILendingAdapter(hook.lendingAdapter());

        uint256 calcDS;

        uint256 calcCL = (preRebalanceTVL * (weight * longLeverage)) / 1e36;

        uint256 calcCS = (((preRebalanceTVL * oraclePriceW()) / 1e18) * (((1e18 - weight) * shortLeverage) / 1e18)) /
            1e30;

        if (shortLeverage != 1e18)
            calcDS = (((calcCS * (1e18 - (1e36 / shortLeverage)) * 1e18) / oraclePriceW()) * (1e18 + slippage)) / 1e24;

        uint256 diffDS = calcDS >= _lendingAdapter.getBorrowedShort()
            ? calcDS - _lendingAdapter.getBorrowedShort()
            : _lendingAdapter.getBorrowedShort() - calcDS;

        assertApproxEqAbs(calcCL, _lendingAdapter.getCollateralLong(), 100);
        assertApproxEqAbs(calcCS, _lendingAdapter.getCollateralShort(), 100);

        if (shortLeverage != 1e18) assertApproxEqAbs((diffDS * 1e18) / calcDS, slippage, slippage);

        uint256 tvlRatio = calcTVL() > preRebalanceTVL
            ? (calcTVL() * 1e18) / preRebalanceTVL - 1e18
            : 1e18 - (calcTVL() * 1e18) / preRebalanceTVL;

        assertApproxEqAbs(tvlRatio, slippage, slippage);
    }

    function assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _leA = ILendingAdapter(hook.lendingAdapter()); // The LA can change in tests
        try this._assertEqPositionState(CL, CS, DL, DS) {
            // Intentionally empty
        } catch {
            console.log("Error: CL", _leA.getCollateralLong());
            console.log("Error: CS", _leA.getCollateralShort());
            console.log("Error: DL", _leA.getBorrowedLong());
            console.log("Error: DS", _leA.getBorrowedShort());
            _assertEqPositionState(CL, CS, DL, DS); // This is to throw the error
        }
    }

    function _assertEqPositionState(uint256 CL, uint256 CS, uint256 DL, uint256 DS) public view {
        ILendingAdapter _leA = ILendingAdapter(hook.lendingAdapter()); // The LA can change in tests
        assertApproxEqAbs(_leA.getCollateralLong(), CL, ASSERT_EQ_PS_THRESHOLD_CL, "CL not equal");
        assertApproxEqAbs(_leA.getCollateralShort(), CS, ASSERT_EQ_PS_THRESHOLD_CS, "CS not equal");
        assertApproxEqAbs(_leA.getBorrowedLong(), DL, ASSERT_EQ_PS_THRESHOLD_DL, "DL not equal");
        assertApproxEqAbs(_leA.getBorrowedShort(), DS, ASSERT_EQ_PS_THRESHOLD_DS, "DS not equal");
    }

    function assertEqProtocolState(uint256 sqrtPriceCurrent, uint256 tvl) public view {
        try this._assertEqProtocolState(sqrtPriceCurrent, tvl) {
            // Intentionally empty
        } catch {
            console.log("Error: sqrtPriceCurrent", hook.sqrtPriceCurrent());
            console.log("Error: tvl", calcTVL());
            _assertEqProtocolState(sqrtPriceCurrent, tvl); // This is to throw the error
        }
    }

    function _assertEqProtocolState(uint256 sqrtPriceCurrent, uint256 tvl) public view {
        assertApproxEqAbs(hook.sqrtPriceCurrent(), sqrtPriceCurrent, 1e1, "sqrtPrice not equal");
        assertApproxEqAbs(calcTVL(), tvl, 1e1, "TVL not equal");
    }

    function _checkSwap(
        uint128 liquidity,
        uint160 preSqrtPrice,
        uint160 postSqrtPrice
    ) public view returns (uint256 deltaX, uint256 deltaY) {
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        LiquidityAmounts.getAmountsForLiquidity(
            preSqrtPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        LiquidityAmounts.getAmountsForLiquidity(
            postSqrtPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        deltaX = SqrtPriceMath.getAmount1Delta(preSqrtPrice, postSqrtPrice, liquidity, true);
        deltaY = SqrtPriceMath.getAmount0Delta(preSqrtPrice, postSqrtPrice, liquidity, false);
    }

    function _liquidityCheck(bool _isInvertedPool, uint256 liquidityMultiplier) public view {
        uint128 liquidityCheck;
        (int24 tickLower, int24 tickUpper) = hook.activeTicks();
        if (_isInvertedPool) {
            liquidityCheck = LiquidityAmounts.getLiquidityForAmount1(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
            );
        } else {
            liquidityCheck = LiquidityAmounts.getLiquidityForAmount0(
                ALMMathLib.getSqrtPriceX96FromTick(tickLower),
                ALMMathLib.getSqrtPriceX96FromTick(tickUpper),
                lendingAdapter.getCollateralLong()
            );
        }

        assertApproxEqAbs(hook.liquidity(), (liquidityCheck * liquidityMultiplier) / 1e18, 1, "liquidity");
    }
}
