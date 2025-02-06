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
import {ILendingPool} from "@src/interfaces/IAave.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract SRebalanceAdapter is Base, IRebalanceAdapter {
    using PRBMathUD60x18 for uint256;
    using TokenWrapperLib for uint256;

    error NoRebalanceNeeded();

    uint160 public sqrtPriceAtLastRebalance;
    uint256 public oraclePriceAtLastRebalance;
    uint256 public timeAtLastRebalance;

    // ** AaveV2
    address constant lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    ILendingPool constant LENDING_POOL = ILendingPool(lendingPool);

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

    function _postSetTokens() internal override {
        IERC20(token0).approve(lendingPool, type(uint256).max);
        IERC20(token1).approve(lendingPool, type(uint256).max);
    }

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
        uint256 priceThreshold = oraclePrice > oraclePriceAtLastRebalance
            ? oraclePrice.div(oraclePriceAtLastRebalance) - 1e18
            : 1e18 - oraclePriceAtLastRebalance.div(oraclePrice);

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

        console.log("slippage %s", slippage);

        (uint256 ethToFl, uint256 usdcToFl, bytes memory data) = _rebalanceCalculations(1e18 + slippage);

        address[] memory assets = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory modes = new uint256[](2);
        (assets[0], amounts[0], modes[0]) = (token0, usdcToFl.unwrap(t0Dec), 0);
        (assets[1], amounts[1], modes[1]) = (token1, ethToFl.unwrap(t1Dec), 0);
        // console.log("ethToFl", ethToFl);
        // console.log("usdcToFl", usdcToFl);
        LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), data, 0);

        console.log("USDC balance before %s", token0BalanceUnwr());
        console.log("WETH balance before %s", token1BalanceUnwr());

        if (token0BalanceUnwr() != 0) lendingAdapter.repayLong((token0BalanceUnwr()).wrap(t0Dec));

        if (token1BalanceUnwr() != 0) lendingAdapter.repayShort((token1BalanceUnwr()).wrap(t1Dec));

        console.log("USDC balance after %s", token0BalanceUnwr());
        console.log("WETH balance after %s", token1BalanceUnwr());

        // ** Check max deviation
        checkDeviations();

        // ** Update state
        //sqrtPriceAtLastRebalance = alm.sqrtPriceCurrent();
        oraclePriceAtLastRebalance = oracle.price();

        sqrtPriceAtLastRebalance = ALMMathLib.getSqrtPriceAtTick(
            ALMMathLib.getTickFromPrice(ALMMathLib.reversePrice(oraclePriceAtLastRebalance))
        );

        alm.updateSqrtPrice(sqrtPriceAtLastRebalance);

        console.log("sqrtPriceAtLastRebalance %s", sqrtPriceAtLastRebalance);

        alm.updateBoundaries();
        timeAtLastRebalance = block.timestamp;
        alm.updateLiquidity(calcLiquidity());

        console.log("RebalanceDone");
    }

    function executeOperation(
        address[] calldata,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata data
    ) external notPaused notShutdown returns (bool) {
        // console.log("executeOperation");
        require(msg.sender == lendingPool, "M0");
        _positionManagement(data);

        // console.log("afterCL %s", lendingAdapter.getCollateralLong());
        // console.log("afterCS %s", lendingAdapter.getCollateralShort());
        // console.log("afterDL %s", lendingAdapter.getBorrowedLong());
        // console.log("afterDS %s", lendingAdapter.getBorrowedShort());

        uint256 borrowedToken0 = amounts[0] + premiums[0];
        uint256 borrowedToken1 = amounts[1] + premiums[1];

        // ** Flash loan management

        console.log("premium0 %s", premiums[0]);
        console.log("premium1 %s", premiums[1]);
        console.log("flDEBT ETH %s", borrowedToken1);
        console.log("wethBalance %s", token1BalanceUnwr());
        console.log("flDEBT USDC %s", borrowedToken0);
        console.log("usdcBalance %s", token0BalanceUnwr());

        if (borrowedToken0 > token0BalanceUnwr()) {
            swapAdapter.swapExactOutput(token1, token0, borrowedToken0 - token0BalanceUnwr());
        }

        console.log("wethBalance after %s", token1BalanceUnwr());
        console.log("usdcBalance after %s", token0BalanceUnwr());

        if (borrowedToken1 > token1BalanceUnwr())
            swapAdapter.swapExactOutput(token0, token1, borrowedToken1 - token1BalanceUnwr());

        console.log("wethBalance after %s", token1BalanceUnwr());
        console.log("usdcBalance after %s", token0BalanceUnwr());

        console.log("here");

        return true;
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _positionManagement(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS, uint256 _targetDL, uint256 _targetDS) = abi
            .decode(data, (int256, int256, int256, int256, uint256, uint256));

        console.log("deltaCL", deltaCL);
        console.log("deltaCS", deltaCS);
        console.log("deltaDL", deltaDL);
        console.log("deltaDS", deltaDS);

        if (deltaCL > 0) lendingAdapter.addCollateralLong(uint256(deltaCL));
        if (deltaCS > 0) lendingAdapter.addCollateralShort(uint256(deltaCS));

        if (deltaDL < 0) lendingAdapter.repayLong(uint256(-deltaDL));
        if (deltaDS < 0) lendingAdapter.repayShort(uint256(-deltaDS));

        if (deltaCL < 0) lendingAdapter.removeCollateralLong(uint256(-deltaCL));
        if (deltaCS < 0) lendingAdapter.removeCollateralShort(uint256(-deltaCS));

        if (deltaDL != 0) lendingAdapter.borrowLong(_targetDL - lendingAdapter.getBorrowedLong());
        if (deltaDS != 0) lendingAdapter.borrowShort(_targetDS - lendingAdapter.getBorrowedShort());
    }

    // --- Math functions --- //

    // @Notice: this function is mainly for removing stack too deep error
    function _rebalanceCalculations(
        uint256 k
    ) internal view returns (uint256 ethToFl, uint256 usdcToFl, bytes memory data) {
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

            console.log("targetCL", targetCL);
            console.log("targetCS", targetCS);
            console.log("targetDL", targetDL);
            console.log("targetDS", targetDS);

            console.log("here");

            deltaCL = int256(targetCL) - int256(lendingAdapter.getCollateralLong());
            deltaCS = int256(targetCS) - int256(lendingAdapter.getCollateralShort());
            deltaDL = int256(targetDL) - int256(lendingAdapter.getBorrowedLong());
            deltaDS = int256(targetDS) - int256(lendingAdapter.getBorrowedShort());

            console.log("deltaCL", deltaCL);
            console.log("deltaCS", deltaCS);
            console.log("deltaDL", deltaDL);
            console.log("deltaDS", deltaDS);
        }

        if (deltaCL > 0) ethToFl += uint256(deltaCL);
        if (deltaCS > 0) usdcToFl += uint256(deltaCS);
        if (deltaDL < 0) usdcToFl += uint256(-deltaDL);
        if (deltaDS < 0) ethToFl += uint256(-deltaDS);

        console.log("k %s", k);
        data = abi.encode(deltaCL, deltaCS, deltaDL, deltaDS, targetDL.mul(k), targetDS.mul(k));
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
        console.log("priceUpper %s", ALMMathLib.reversePrice(ALMMathLib.getPriceFromTick(alm.tickUpper())));
        console.log("priceLower %s", ALMMathLib.reversePrice(ALMMathLib.getPriceFromTick(alm.tickLower())));

        uint256 liquidity = ALMMathLib.getL(
            VLP,
            oraclePriceAtLastRebalance,
            ALMMathLib.reversePrice(ALMMathLib.getPriceFromTick(alm.tickUpper())),
            ALMMathLib.reversePrice(ALMMathLib.getPriceFromTick(alm.tickLower()))
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
