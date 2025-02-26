// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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
    bool public isInvertAssets;
    bool public isUnicord;

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

    function setIsUnicord(bool _isUnicord) external onlyOwner {
        isUnicord = _isUnicord;
    }

    // ** Logic

    function isRebalanceNeeded() public view returns (bool, uint256, uint256) {
        (bool _isPriceRebalance, uint256 priceThreshold) = isPriceRebalance();
        (bool _isTimeRebalance, uint256 auctionTriggerTime) = isTimeRebalance();

        return (_isPriceRebalance || _isTimeRebalance, priceThreshold, auctionTriggerTime);
    }

    function isPriceRebalance() public view returns (bool, uint256) {
        uint256 oraclePrice = oracle.price();
        uint256 cachedRatio = oraclePrice.div(oraclePriceAtLastRebalance);
        uint256 priceThreshold = oraclePrice > oraclePriceAtLastRebalance ? cachedRatio - 1e18 : 1e18 - cachedRatio;

        return (priceThreshold >= rebalancePriceThreshold, priceThreshold);
    }

    function isTimeRebalance() public view returns (bool, uint256) {
        uint256 auctionTriggerTime = timeAtLastRebalance + rebalanceTimeThreshold;
        return (block.timestamp >= auctionTriggerTime, auctionTriggerTime);
    }

    function rebalance(uint256 slippage) external onlyOwner notPaused notShutdown {
        (bool isRebalance, , ) = isRebalanceNeeded();
        if (!isRebalance) revert NoRebalanceNeeded();
        alm.refreshReserves();

        (uint256 baseToFl, uint256 quoteToFl, bytes memory data) = _rebalanceCalculations(1e18 + slippage);

        lendingAdapter.flashLoanTwoTokens(base, baseToFl.unwrap(bDec), quote, quoteToFl.unwrap(qDec), data);

        if (isUnicord) {
            if (baseBalanceUnwr() != 0) lendingAdapter.addCollateralShort((baseBalanceUnwr()).wrap(bDec));
            if (quoteBalanceUnwr() != 0) lendingAdapter.addCollateralLong((quoteBalanceUnwr()).wrap(qDec));
        } else {
            if (baseBalanceUnwr() != 0) lendingAdapter.repayLong((baseBalanceUnwr()).wrap(bDec));
            if (quoteBalanceUnwr() != 0) lendingAdapter.repayShort((quoteBalanceUnwr()).wrap(qDec));
        }

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
    }

    function onFlashLoanTwoTokens(
        address base,
        uint256 amountB,
        address quote,
        uint256 amountQ,
        bytes calldata data
    ) external notPaused notShutdown onlyLendingAdapter {
        _positionManagement(data);
        if (amountB > baseBalanceUnwr()) swapAdapter.swapExactOutput(quote, base, amountB - baseBalanceUnwr());
        if (amountQ > quoteBalanceUnwr()) swapAdapter.swapExactOutput(base, quote, amountQ - quoteBalanceUnwr());
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _positionManagement(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS) = abi.decode(
            data,
            (int256, int256, int256, int256)
        );
        if (deltaCL > 0) lendingAdapter.addCollateralLong(uint256(deltaCL));
        if (deltaCS > 0) lendingAdapter.addCollateralShort(uint256(deltaCS));
        if (deltaDL < 0) lendingAdapter.repayLong(uint256(-deltaDL));
        if (deltaDS < 0) lendingAdapter.repayShort(uint256(-deltaDS));
        if (deltaCL < 0) lendingAdapter.removeCollateralLong(uint256(-deltaCL));
        if (deltaCS < 0) lendingAdapter.removeCollateralShort(uint256(-deltaCS));
        if (deltaDL > 0) lendingAdapter.borrowLong(uint256(deltaDL));
        if (deltaDS > 0) lendingAdapter.borrowShort(uint256(deltaDS));
    }

    // --- Math functions --- //

    // @Notice: this function is mainly for removing stack too deep error
    function _rebalanceCalculations(
        uint256 k
    ) internal view returns (uint256 baseToFl, uint256 quoteToFl, bytes memory data) {
        uint256 targetDL;
        uint256 targetDS;
        int256 deltaCL;
        int256 deltaCS;
        int256 deltaDL;
        int256 deltaDS;
        {
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

            if (isUnicord) {
                // @Notice: discount to cover slippage
                targetCL = targetCL.mul(2e18 - k);
                targetCS = targetCS.mul(2e18 - k);

                // @Notice: no debt operations in unicord
                targetDL = 0;
                targetDS = 0;
            } else {
                // @Notice: borrow additional funds to cover slippage
                targetDL = targetDL.mul(k);
                targetDS = targetDS.mul(k);
            }

            deltaCL = int256(targetCL) - int256(lendingAdapter.getCollateralLong());
            deltaCS = int256(targetCS) - int256(lendingAdapter.getCollateralShort());
            deltaDL = int256(targetDL) - int256(lendingAdapter.getBorrowedLong());
            deltaDS = int256(targetDS) - int256(lendingAdapter.getBorrowedShort());
        }

        if (deltaCL > 0) quoteToFl += uint256(deltaCL);
        if (deltaCS > 0) baseToFl += uint256(deltaCS);
        if (deltaDL < 0) baseToFl += uint256(-deltaDL);
        if (deltaDS < 0) quoteToFl += uint256(-deltaDS);

        data = abi.encode(deltaCL, deltaCS, deltaDL, deltaDS);
    }

    function calcLiquidity() public view returns (uint128) {
        uint256 VLP;
        if (isInvertAssets) VLP = ALMMathLib.getVLP(alm.TVL(), weight, longLeverage, shortLeverage);
        else VLP = ALMMathLib.getVLP(alm.TVL(), weight, longLeverage, shortLeverage).mul(oracle.price());

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
        return uint128(liquidity);
    }

    function checkDeviations() internal view {
        uint256 price = oracle.price();
        uint256 currentCL = lendingAdapter.getCollateralLong();
        uint256 currentCS = lendingAdapter.getCollateralShort();

        uint256 _longLeverage = (currentCL.mul(price)).div(currentCL.mul(price) - lendingAdapter.getBorrowedLong());
        uint256 _shortLeverage = currentCS.div(currentCS - lendingAdapter.getBorrowedShort().mul(price));

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
