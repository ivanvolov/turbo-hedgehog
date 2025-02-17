// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** v4 imports
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract SRebalanceAdapter is Base, IRebalanceAdapter {
    using PRBMathUD60x18 for uint256;
    using TokenWrapperLib for uint256;

    error NoRebalanceNeeded();

    uint160 public sqrtPriceAtLastRebalance;
    uint256 public oraclePriceAtLastRebalance;
    uint256 public timeAtLastRebalance;

    // ** Parameters
    uint256 public rebalancePriceThreshold;
    uint256 public rebalanceTimeThreshold;
    uint256 public weight;
    uint256 public longLeverage;
    uint256 public shortLeverage;
    uint256 public maxDeviationLong;
    uint256 public maxDeviationShort;
    bool public isInvertAssets = false;

    constructor() Base(msg.sender) {}

    function setRebalancePriceThreshold(uint256 _rebalancePriceThreshold) external onlyOwner {
        rebalancePriceThreshold = _rebalancePriceThreshold;
    }

    function setSqrtPriceAtLastRebalance(uint160 _sqrtPriceAtLastRebalance) external onlyOwner {
        sqrtPriceAtLastRebalance = _sqrtPriceAtLastRebalance;
    }

    function setOraclePriceAtLastRebalance(uint256 _oraclePriceAtLastRebalance) external onlyOwner {
        oraclePriceAtLastRebalance = _oraclePriceAtLastRebalance;
    }

    function setTimeAtLastRebalance(uint256 _timeAtLastRebalance) external onlyOwner {
        timeAtLastRebalance = _timeAtLastRebalance;
    }

    function setRebalanceTimeThreshold(uint256 _rebalanceTimeThreshold) external onlyOwner {
        rebalanceTimeThreshold = _rebalanceTimeThreshold;
    }

    function setWeight(uint256 _weight) external onlyOwner {
        weight = _weight;
    }

    function setLongLeverage(uint256 _longLeverage) external onlyOwner {
        longLeverage = _longLeverage;
    }

    function setShortLeverage(uint256 _shortLeverage) external onlyOwner {
        shortLeverage = _shortLeverage;
    }

    function setMaxDeviationLong(uint256 _maxDeviationLong) external onlyOwner {
        maxDeviationLong = _maxDeviationLong;
    }

    function setMaxDeviationShort(uint256 _maxDeviationShort) external onlyOwner {
        maxDeviationShort = _maxDeviationShort;
    }

    function setIsInvertAssets(bool _isInvertAssets) external onlyOwner {
        isInvertAssets = _isInvertAssets;
    }

    // ** Logic

    function isRebalanceNeeded() public view returns (bool, uint256, uint256) {
        (bool _isPriceRebalance, uint256 priceThreshold) = isPriceRebalance();
        (bool _isTimeRebalance, uint256 auctionTriggerTime) = isTimeRebalance();

        console.log("auctionTriggerTime %s", auctionTriggerTime);
        return (_isPriceRebalance || _isTimeRebalance, priceThreshold, auctionTriggerTime);
    }

    function isPriceRebalance() public view returns (bool, uint256) {
        console.log("currentPrice %s", oracle.price());
        console.log("priceAtLastRebalance %s", oraclePriceAtLastRebalance);

        uint256 oraclePrice = oracle.price();
        uint256 cachedRatio = oraclePrice.div(oraclePriceAtLastRebalance);
        uint256 priceThreshold = oraclePrice > oraclePriceAtLastRebalance ? cachedRatio - 1e18 : 1e18 - cachedRatio;

        console.log("priceThreshold %s", priceThreshold);

        return (priceThreshold >= rebalancePriceThreshold, priceThreshold);
    }

    function isTimeRebalance() public view returns (bool, uint256) {
        uint256 auctionTriggerTime = timeAtLastRebalance + rebalanceTimeThreshold;
        return (block.timestamp >= auctionTriggerTime, auctionTriggerTime);
    }

    function rebalance(uint256 slippage) external onlyOwner notPaused notShutdown {
        console.log("Rebalance");

        (bool isRebalance, , ) = isRebalanceNeeded();
        if (!isRebalance) revert NoRebalanceNeeded();
        alm.refreshReserves();

        // console.log("slippage %s", slippage);

        (uint256 baseToFl, uint256 quoteToFl, bytes memory data) = _rebalanceCalculations(1e18 + slippage);
        console.log("basefl %s", baseToFl.unwrap(bDec));
        console.log("quotefl %s", quoteToFl.unwrap(qDec));
        lendingAdapter.flashLoanTwoTokens(base, baseToFl.unwrap(bDec), quote, quoteToFl.unwrap(qDec), data);

        console.log("USDC balance before %s", baseBalanceUnwr());
        console.log("WETH balance before %s", quoteBalanceUnwr());

        if (baseBalanceUnwr() != 0) lendingAdapter.repayLong((baseBalanceUnwr()).wrap(bDec));
        if (quoteBalanceUnwr() != 0) lendingAdapter.repayShort((quoteBalanceUnwr()).wrap(qDec));

        console.log("USDC balance after %s", baseBalanceUnwr());
        console.log("WETH balance after %s", quoteBalanceUnwr());

        // ** Check max deviation
        checkDeviations();

        // ** Update state
        oraclePriceAtLastRebalance = oracle.price();

        sqrtPriceAtLastRebalance = ALMMathLib.getSqrtPriceAtTick(
            ALMMathLib.getTickFromPrice(
                ALMMathLib.getPoolPriceFromOraclePrice(
                    oraclePriceAtLastRebalance,
                    alm.isInvertedPool(),
                    uint8(ALMMathLib.absSub(bDec, qDec))
                )
            )
        );

        alm.updateSqrtPrice(sqrtPriceAtLastRebalance);

        alm.updateBoundaries();
        timeAtLastRebalance = block.timestamp;
        alm.updateLiquidity(calcLiquidity());

        console.log("RebalanceDone");
    }

    function onFlashLoanTwoTokens(
        address base,
        uint256 amount0,
        address quote,
        uint256 amount1,
        bytes calldata data
    ) external notPaused notShutdown onlyLendingAdapter {
        console.log("> onFlashLoanTwoTokens");
        _positionManagement(data);
        // console.log("afterCL %s", lendingAdapter.getCollateralLong());
        // console.log("afterCS %s", lendingAdapter.getCollateralShort());
        // console.log("afterDL %s", lendingAdapter.getBorrowedLong());
        // console.log("afterDS %s", lendingAdapter.getBorrowedShort());

        // ** Flash loan management
        console.log("flDEBT ETH %s", amount1);
        console.log("wethBalance %s", quoteBalanceUnwr());
        console.log("flDEBT USDC %s", amount0);
        console.log("usdcBalance %s", baseBalanceUnwr());

        if (amount0 > baseBalanceUnwr()) swapAdapter.swapExactOutput(quote, base, amount0 - baseBalanceUnwr());

        console.log("wethBalance after %s", quoteBalanceUnwr());
        console.log("usdcBalance after %s", baseBalanceUnwr());

        if (amount1 > quoteBalanceUnwr()) swapAdapter.swapExactOutput(base, quote, amount1 - quoteBalanceUnwr());

        console.log("wethBalance after %s", quoteBalanceUnwr());
        console.log("usdcBalance after %s", baseBalanceUnwr());
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _positionManagement(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS) = abi.decode(
            data,
            (int256, int256, int256, int256)
        );

        console.log("(1)");
        if (deltaCL > 0) lendingAdapter.addCollateralLong(uint256(deltaCL));
        console.log("(2)");
        if (deltaCS > 0) lendingAdapter.addCollateralShort(uint256(deltaCS));
        console.log("(3)");

        if (deltaDL < 0) lendingAdapter.repayLong(uint256(-deltaDL));
        console.log("(4)");
        if (deltaDS < 0) lendingAdapter.repayShort(uint256(-deltaDS));
        console.log("(5)");

        if (deltaCL < 0) lendingAdapter.removeCollateralLong(uint256(-deltaCL));
        console.log("(6)");
        if (deltaCS < 0) lendingAdapter.removeCollateralShort(uint256(-deltaCS));
        console.log("(7)");

        console.log("CL %s", (lendingAdapter.getCollateralLong()).unwrap(qDec));
        console.log("CS %s", (lendingAdapter.getCollateralShort()).unwrap(bDec));

        console.log("deltaDL %s", uint256(deltaDL).unwrap(bDec));
        console.log("deltaDS %s", uint256(deltaDS).unwrap(qDec));

        if (deltaDL > 0) lendingAdapter.borrowLong(uint256(deltaDL));
        console.log("(8)");
        if (deltaDS > 0) lendingAdapter.borrowShort(uint256(deltaDS));
        console.log("(9)");
    }

    // --- Math functions --- //

    // @Notice: this function is mainly for removing stack too deep error
    function _rebalanceCalculations(
        uint256 k
    ) internal view returns (uint256 baseToFl, uint256 quoteToFl, bytes memory data) {
        // console.log("> rebalanceCalculations");
        // console.log("k %s", k);
        uint256 targetDL;
        uint256 targetDS;

        int256 deltaCL;
        int256 deltaCS;
        int256 deltaDL;
        int256 deltaDS;
        {
            console.log("price %s", oracle.price());
            console.log("currentCL", lendingAdapter.getCollateralLong());
            console.log("currentCS", lendingAdapter.getCollateralShort());
            console.log("currentDL", lendingAdapter.getBorrowedLong());
            console.log("currentDS", lendingAdapter.getBorrowedShort());
            console.log("preTVL %s", alm.TVL());

            uint256 targetCL;
            uint256 targetCS;
            uint256 price = oracle.price();
            if (isInvertAssets) {
                targetCL = alm.TVL().mul(weight).mul(longLeverage).div(price);
                targetCS = alm.TVL().mul(1e18 - weight).mul(shortLeverage);

                targetDL = targetCL.mul(price).mul(1e18 - uint256(1e18).div(longLeverage));
                targetDS = targetCS.div(price).mul(1e18 - uint256(1e18).div(shortLeverage));
            } else {
                targetCL = alm.TVL().mul(weight).mul(longLeverage);
                targetCS = alm.TVL().mul(1e18 - weight).mul(shortLeverage).mul(price);

                targetDL = targetCL.mul(price).mul(1e18 - uint256(1e18).div(longLeverage));
                targetDS = targetCS.div(price).mul(1e18 - uint256(1e18).div(shortLeverage));
            }

            //borrow additional funds to cover slippage
            targetDL = targetDL.mul(k);
            targetDS = targetDS.mul(k);

            console.log("targetCL", targetCL);
            console.log("targetCS", targetCS);
            console.log("targetDL", targetDL);
            console.log("targetDS", targetDS);

            deltaCL = int256(targetCL) - int256(lendingAdapter.getCollateralLong());
            deltaCS = int256(targetCS) - int256(lendingAdapter.getCollateralShort());
            deltaDL = int256(targetDL) - int256(lendingAdapter.getBorrowedLong());
            deltaDS = int256(targetDS) - int256(lendingAdapter.getBorrowedShort());

            console.log("deltaCL", deltaCL);
            console.log("deltaCS", deltaCS);
            console.log("deltaDL", deltaDL);
            console.log("deltaDS", deltaDS);
        }

        if (deltaCL > 0) quoteToFl += uint256(deltaCL);
        if (deltaCS > 0) baseToFl += uint256(deltaCS);
        if (deltaDL < 0) baseToFl += uint256(-deltaDL);
        if (deltaDS < 0) quoteToFl += uint256(-deltaDS);

        console.log("k %s", k);

        console.log("baseToFl %s", baseToFl);
        console.log("quoteToFl %s", quoteToFl);

        data = abi.encode(deltaCL, deltaCS, deltaDL, deltaDS);
    }

    function calcLiquidity() public view returns (uint128) {
        console.log("post TVL %s", alm.TVL());

        uint256 VLP;
        if (isInvertAssets) {
            VLP = ALMMathLib.getVLP(alm.TVL(), weight, longLeverage, shortLeverage);
        } else {
            VLP = ALMMathLib.getVLP(alm.TVL(), weight, longLeverage, shortLeverage).mul(oracle.price());
        }

        console.log("VLP %s", VLP);
        console.log("currentOraclePrice %s", oracle.price());
        console.log("priceAtLastRebalance      %s", oraclePriceAtLastRebalance);
        console.log(
            "priceUpper %s",
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickUpper()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(bDec, qDec))
            )
        );
        console.log(
            "priceLower %s",
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickLower()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(bDec, qDec))
            )
        );

        uint256 liquidity = ALMMathLib.getL(
            VLP,
            oraclePriceAtLastRebalance,
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickUpper()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(bDec, qDec))
            ),
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickLower()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(bDec, qDec))
            )
        );
        console.log("liquidity %s", liquidity);
        return uint128(liquidity);
    }

    function checkDeviations() internal view {
        uint256 price = oracle.price();
        uint256 currentCL = lendingAdapter.getCollateralLong();
        uint256 currentCS = lendingAdapter.getCollateralShort();

        console.log("CL after %s", currentCL);
        console.log("CS after %s", currentCS);
        console.log("DL after %s", lendingAdapter.getBorrowedLong());
        console.log("DS after %s", lendingAdapter.getBorrowedShort());

        uint256 _longLeverage = (currentCL.mul(price)).div(currentCL.mul(price) - lendingAdapter.getBorrowedLong());
        uint256 _shortLeverage = currentCS.div(currentCS - lendingAdapter.getBorrowedShort().mul(price));

        console.log("longLeverage %s", _longLeverage);
        console.log("shortLeverage %s", _shortLeverage);
        console.log("TVL after %s", alm.TVL());

        uint256 deviationLong = ALMMathLib.absSub(_longLeverage, longLeverage);
        uint256 deviationShort = ALMMathLib.absSub(_shortLeverage, shortLeverage);
        require(deviationLong <= maxDeviationLong, "D1");
        require(deviationShort <= maxDeviationShort, "D2");
    }

    // --- Helpers --- //

    function baseBalanceUnwr() internal view returns (uint256) {
        return IERC20(base).balanceOf(address(this));
    }

    function quoteBalanceUnwr() internal view returns (uint256) {
        return IERC20(quote).balanceOf(address(this));
    }
}
