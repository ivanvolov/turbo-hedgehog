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
    bool public invertAssets = false;

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
        invertAssets = _isInvertAssets;
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

        (uint256 token0ToFl, uint256 token1ToFl, bytes memory data) = _rebalanceCalculations(1e18 + slippage);
        console.log("token0fl %s", token0ToFl.unwrap(t0Dec));
        console.log("token1fl %s", token1ToFl.unwrap(t1Dec));
        lendingAdapter.flashLoanTwoTokens(token0, token0ToFl.unwrap(t0Dec), token1, token1ToFl.unwrap(t1Dec), data);

        console.log("USDC balance before %s", token0BalanceUnwr());
        console.log("WETH balance before %s", token1BalanceUnwr());

        if (token0BalanceUnwr() != 0) lendingAdapter.repayLong((token0BalanceUnwr()).wrap(t0Dec));
        if (token1BalanceUnwr() != 0) lendingAdapter.repayShort((token1BalanceUnwr()).wrap(t1Dec));

        console.log("USDC balance after %s", token0BalanceUnwr());
        console.log("WETH balance after %s", token1BalanceUnwr());

        // ** Check max deviation
        checkDeviations();

        // ** Update state
        oraclePriceAtLastRebalance = oracle.price();

        sqrtPriceAtLastRebalance = ALMMathLib.getSqrtPriceAtTick(
            ALMMathLib.getTickFromPrice(
                ALMMathLib.getPoolPriceFromOraclePrice(
                    oraclePriceAtLastRebalance,
                    alm.isInvertedPool(),
                    uint8(ALMMathLib.absSub(t0Dec, t1Dec))
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
        address token0,
        uint256 amount0,
        address token1,
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
        console.log("wethBalance %s", token1BalanceUnwr());
        console.log("flDEBT USDC %s", amount0);
        console.log("usdcBalance %s", token0BalanceUnwr());

        if (amount0 > token0BalanceUnwr()) swapAdapter.swapExactOutput(token1, token0, amount0 - token0BalanceUnwr());

        console.log("wethBalance after %s", token1BalanceUnwr());
        console.log("usdcBalance after %s", token0BalanceUnwr());

        if (amount1 > token1BalanceUnwr()) swapAdapter.swapExactOutput(token0, token1, amount1 - token1BalanceUnwr());

        console.log("wethBalance after %s", token1BalanceUnwr());
        console.log("usdcBalance after %s", token0BalanceUnwr());
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

        console.log("CL %s", (lendingAdapter.getCollateralLong()).unwrap(t1Dec));
        console.log("CS %s", (lendingAdapter.getCollateralShort()).unwrap(t0Dec));

        console.log("deltaDL %s", uint256(deltaDL).unwrap(t0Dec));
        console.log("deltaDS %s", uint256(deltaDS).unwrap(t1Dec));

        if (deltaDL > 0) lendingAdapter.borrowLong(uint256(deltaDL));
        console.log("(8)");
        if (deltaDS > 0) lendingAdapter.borrowShort(uint256(deltaDS));
        console.log("(9)");
    }

    // --- Math functions --- //

    // @Notice: this function is mainly for removing stack too deep error
    function _rebalanceCalculations(
        uint256 k
    ) internal view returns (uint256 token0ToFl, uint256 token1ToFl, bytes memory data) {
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
            if (invertAssets) {
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

        if (deltaCL > 0) token1ToFl += uint256(deltaCL);
        if (deltaCS > 0) token0ToFl += uint256(deltaCS);
        if (deltaDL < 0) token0ToFl += uint256(-deltaDL);
        if (deltaDS < 0) token1ToFl += uint256(-deltaDS);

        console.log("k %s", k);

        console.log("token0ToFl %s", token0ToFl);
        console.log("token1ToFl %s", token1ToFl);

        data = abi.encode(deltaCL, deltaCS, deltaDL, deltaDS);
    }

    function calcLiquidity() public view returns (uint128) {
        console.log("post TVL %s", alm.TVL());

        uint256 VLP;
        if (invertAssets) {
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
                uint8(ALMMathLib.absSub(t0Dec, t1Dec))
            )
        );
        console.log(
            "priceLower %s",
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickLower()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(t0Dec, t1Dec))
            )
        );

        uint256 liquidity = ALMMathLib.getL(
            VLP,
            oraclePriceAtLastRebalance,
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickUpper()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(t0Dec, t1Dec))
            ),
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickLower()),
                alm.isInvertedPool(),
                uint8(ALMMathLib.absSub(t0Dec, t1Dec))
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

    function token0BalanceUnwr() internal view returns (uint256) {
        return IERC20(token0).balanceOf(address(this));
    }

    function token1BalanceUnwr() internal view returns (uint256) {
        return IERC20(token1).balanceOf(address(this));
    }
}
