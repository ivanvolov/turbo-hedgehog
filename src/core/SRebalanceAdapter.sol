// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18, PRBMath} from "@prb-math/PRBMathUD60x18.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ** libraries
import {ALMMathLib} from "../libraries/ALMMathLib.sol";
import {TokenWrapperLib} from "../libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "./base/Base.sol";

// ** interfaces
import {IRebalanceAdapter} from "../interfaces/IRebalanceAdapter.sol";

contract SRebalanceAdapter is Base, IRebalanceAdapter {
    error RebalanceConditionNotMet();
    error NotRebalanceOperator();
    error LeverageValuesNotValid();

    /// @notice Emitted when the rebalance is triggered.
    /// @param slippage                The execution slippage, as a UD60x18 value.
    /// @param oraclePriceAtRebalance  The oracle’s price at last rebalance, as a UD60x18 value.
    event Rebalance(
        uint256 indexed priceThreshold,
        uint256 indexed auctionTriggerTime,
        uint256 slippage,
        uint128 liquidity,
        uint256 oraclePriceAtRebalance,
        uint160 sqrtPriceAtRebalance
    );
    event LastRebalanceSnapshotSet(uint256 indexed oraclePrice, uint160 indexed sqrtPrice, uint256 indexed timestamp);
    event RebalanceConstraintsSet(
        uint256 priceThreshold,
        uint256 timeThreshold,
        uint256 maxDevLong,
        uint256 maxDevShort
    );
    event RebalanceParamsSet(uint256 weight, uint256 longLeverage, uint256 shortLeverage);
    event RebalanceOperatorSet(address indexed operator);

    using PRBMathUD60x18 for uint256;
    using TokenWrapperLib for uint256;

    // ** Last rebalance snapshot
    uint160 public sqrtPriceAtLastRebalance;
    uint256 public oraclePriceAtLastRebalance;
    uint256 public timeAtLastRebalance;

    // ** Parameters
    /// @notice The target portfolio weight for long vs short, encoded as a UD60x18 value.
    ///         (i.e. real_weight × 1e18, where 1 = 100%).
    uint256 public weight;

    /// @notice The leverage multiplier applied to long positions, encoded as a UD60x18 value.
    ///         (i.e. real_leverage × 1e18, where 2 = 2×leverage)
    uint256 public longLeverage;

    /// @notice The leverage multiplier applied to short positions, encoded as a UD60x18 value.
    ///         (i.e. real_leverage × 1e18, where 2 = 2×leverage).
    uint256 public shortLeverage;

    /// @notice The multiplier applied to the virtual liquidity, encoded as a UD60x18 value.
    ///         (i.e. virtual_liquidity × 1e18, where 1 = 100%).
    uint256 public liquidityMultiplier;

    uint256 public rebalancePriceThreshold;
    uint256 public rebalanceTimeThreshold;
    uint256 public maxDeviationLong;
    uint256 public maxDeviationShort;
    bool public immutable isInvertedPool;
    bool public immutable isInvertedAssets;
    bool public immutable isNova;
    address public rebalanceOperator;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        bool _isInvertedPool,
        bool _isInvertedAssets,
        bool _isNova
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        isInvertedPool = _isInvertedPool;
        isInvertedAssets = _isInvertedAssets;
        isNova = _isNova;
    }

    function setLastRebalanceSnapshot(
        uint256 _oraclePriceAtLastRebalance,
        uint160 _sqrtPriceAtLastRebalance,
        uint256 _timeAtLastRebalance
    ) external onlyOwner {
        oraclePriceAtLastRebalance = _oraclePriceAtLastRebalance;
        sqrtPriceAtLastRebalance = _sqrtPriceAtLastRebalance;
        timeAtLastRebalance = _timeAtLastRebalance;

        emit LastRebalanceSnapshotSet(_oraclePriceAtLastRebalance, _sqrtPriceAtLastRebalance, _timeAtLastRebalance);
    }

    function setRebalanceConstraints(
        uint256 _rebalancePriceThreshold,
        uint256 _rebalanceTimeThreshold,
        uint256 _maxDeviationLong,
        uint256 _maxDeviationShort
    ) external onlyOwner {
        rebalancePriceThreshold = _rebalancePriceThreshold;
        rebalanceTimeThreshold = _rebalanceTimeThreshold;
        maxDeviationLong = _maxDeviationLong;
        maxDeviationShort = _maxDeviationShort;

        emit RebalanceConstraintsSet(
            _rebalancePriceThreshold,
            _rebalanceTimeThreshold,
            _maxDeviationLong,
            _maxDeviationShort
        );
    }

    function setRebalanceParams(
        uint256 _weight,
        uint256 _liquidityMultiplier,
        uint256 _longLeverage,
        uint256 _shortLeverage
    ) external onlyOwner {
        if (longLeverage < shortLeverage) revert LeverageValuesNotValid();
        weight = _weight;
        liquidityMultiplier = _liquidityMultiplier;
        longLeverage = _longLeverage;
        shortLeverage = _shortLeverage;

        emit RebalanceParamsSet(_weight, _longLeverage, _shortLeverage);
    }

    function setRebalanceOperator(address _rebalanceOperator) external onlyOwner {
        rebalanceOperator = _rebalanceOperator;
        emit RebalanceOperatorSet(_rebalanceOperator);
    }

    // ** Logic

    /// @notice Computes when the next rebalance can be triggered
    /// @return needRebalance   True if rebalance is allowed, false otherwise
    /// @return priceThreshold  The current price threshold for the price based rebalance
    /// @return triggerTime     The exact timestamp when a time-based rebalance is allowed
    function isRebalanceNeeded() public view returns (bool, uint256, uint256) {
        (bool _isPriceRebalance, uint256 _priceThreshold) = isPriceRebalance();
        (bool _isTimeRebalance, uint256 _triggerTime) = isTimeRebalance();
        return (_isPriceRebalance || _isTimeRebalance, _priceThreshold, _triggerTime);
    }

    /// @notice Computes when the next price‐based rebalance can be triggered
    /// @return needRebalance   True if rebalance is allowed, false otherwise
    /// @return priceThreshold  The current price threshold for the price based rebalance
    function isPriceRebalance() public view returns (bool needRebalance, uint256 priceThreshold) {
        uint256 oraclePrice = oracle.price();
        uint256 cachedRatio = oraclePrice.div(oraclePriceAtLastRebalance);
        priceThreshold = oraclePrice > oraclePriceAtLastRebalance ? cachedRatio - 1e18 : 1e18 - cachedRatio;

        needRebalance = priceThreshold >= rebalancePriceThreshold;
    }

    /// @notice Computes when the next time‐based rebalance can be triggered
    /// @return needRebalance  True if rebalance is allowed, false otherwise
    /// @return triggerTime    The exact timestamp when a time-based rebalance is allowed
    function isTimeRebalance() public view returns (bool needRebalance, uint256 triggerTime) {
        triggerTime = timeAtLastRebalance + rebalanceTimeThreshold;
        needRebalance = block.timestamp >= triggerTime;
    }

    function rebalance(uint256 slippage) external notPaused notShutdown onlyRebalanceOperator {
        (bool isRebalance, uint256 priceThreshold, uint256 auctionTriggerTime) = isRebalanceNeeded();
        if (!isRebalance) revert RebalanceConditionNotMet();
        alm.refreshReserves();
        alm.transferFees();

        (uint256 baseToFl, uint256 quoteToFl, bytes memory data) = _rebalanceCalculations(1e18 + slippage);

        if (isNova) {
            if (quoteToFl != 0) flashLoanAdapter.flashLoanSingle(quote, quoteToFl.unwrap(qDec), data);
            else flashLoanAdapter.flashLoanSingle(base, baseToFl.unwrap(bDec), data);
            uint256 baseBalance = baseBalanceUnwr();
            if (baseBalance != 0) lendingAdapter.addCollateralShort(baseBalance.wrap(bDec));
            uint256 quoteBalance = quoteBalanceUnwr();
            if (quoteBalance != 0) lendingAdapter.addCollateralLong(quoteBalance.wrap(qDec));
        } else {
            flashLoanAdapter.flashLoanTwoTokens(base, baseToFl.unwrap(bDec), quote, quoteToFl.unwrap(qDec), data);
            uint256 baseBalance = baseBalanceUnwr();
            if (baseBalance != 0) lendingAdapter.repayLong(baseBalance.wrap(bDec));
            uint256 quoteBalance = quoteBalanceUnwr();
            if (quoteBalance != 0) lendingAdapter.repayShort(quoteBalance.wrap(qDec));
        }

        // ** Check max deviation
        checkDeviations();

        // ** Update state
        oraclePriceAtLastRebalance = oracle.price();

        sqrtPriceAtLastRebalance = ALMMathLib.getSqrtPriceAtTick(
            ALMMathLib.getTickFromPrice(
                ALMMathLib.getPoolPriceFromOraclePrice(oraclePriceAtLastRebalance, isInvertedPool, decimalsDelta)
            )
        );

        alm.updateSqrtPrice(sqrtPriceAtLastRebalance);

        alm.updateBoundaries();
        timeAtLastRebalance = block.timestamp;
        uint128 liquidity = calcLiquidity();
        alm.updateLiquidity(liquidity);

        emit Rebalance(
            priceThreshold,
            auctionTriggerTime,
            slippage,
            liquidity,
            oraclePriceAtLastRebalance,
            sqrtPriceAtLastRebalance
        );
    }

    function onFlashLoanSingle(
        IERC20 token,
        uint256 amount,
        bytes calldata data
    ) external notPaused notShutdown onlyFlashLoanAdapter {
        _managePositionDeltas(data);
        uint256 balance = token.balanceOf(address(this));
        if (amount > balance) swapAdapter.swapExactOutput(otherToken(token), token, amount - balance);
    }

    function onFlashLoanTwoTokens(
        IERC20 base,
        uint256 amountB,
        IERC20 quote,
        uint256 amountQ,
        bytes calldata data
    ) external notPaused notShutdown onlyFlashLoanAdapter {
        _managePositionDeltas(data);

        uint256 baseBalanceUnwr = base.balanceOf(address(this));
        if (amountB > baseBalanceUnwr) swapAdapter.swapExactOutput(quote, base, amountB - baseBalanceUnwr);
        else {
            uint256 quoteBalanceUnwr = quote.balanceOf(address(this));
            if (amountQ > quoteBalanceUnwr) swapAdapter.swapExactOutput(base, quote, amountQ - quoteBalanceUnwr);
        }
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _managePositionDeltas(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS) = abi.decode(
            data,
            (int256, int256, int256, int256)
        );
        lendingAdapter.updatePosition(deltaCL, deltaCS, deltaDL, deltaDS);
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
            uint256 TVL = alm.TVL();
            if (isInvertedAssets) {
                targetCL = PRBMath.mulDiv(TVL.mul(weight), longLeverage, price);
                targetCS = TVL.mul(1e18 - weight).mul(shortLeverage);
            } else {
                targetCL = TVL.mul(weight).mul(longLeverage);
                targetCS = TVL.mul(1e18 - weight).mul(shortLeverage).mul(price);
            }

            targetDL = targetCL.mul(price).mul(1e18 - uint256(1e18).div(longLeverage));
            targetDS = PRBMath.mulDiv(targetCS, 1e18 - uint256(1e18).div(shortLeverage), price);

            if (isNova) {
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

            (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
            deltaCL = SafeCast.toInt256(targetCL) - SafeCast.toInt256(CL);
            deltaCS = SafeCast.toInt256(targetCS) - SafeCast.toInt256(CS);
            deltaDL = SafeCast.toInt256(targetDL) - SafeCast.toInt256(DL);
            deltaDS = SafeCast.toInt256(targetDS) - SafeCast.toInt256(DS);
        }

        if (deltaCL > 0) quoteToFl += uint256(deltaCL);
        if (deltaCS > 0) baseToFl += uint256(deltaCS);
        if (deltaDL < 0) baseToFl += uint256(-deltaDL);
        if (deltaDS < 0) quoteToFl += uint256(-deltaDS);

        data = abi.encode(deltaCL, deltaCS, deltaDL, deltaDS);
    }

    function calcLiquidity() public view returns (uint128) {
        uint256 value = ALMMathLib.getVirtualValue(alm.TVL(), weight, longLeverage, shortLeverage);
        if (!isInvertedAssets) value = value.mul(oracle.price());

        uint256 liquidity = ALMMathLib.getVirtualLiquidity(
            value,
            oraclePriceAtLastRebalance,
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickUpper()),
                isInvertedPool,
                decimalsDelta
            ),
            ALMMathLib.getOraclePriceFromPoolPrice(
                ALMMathLib.getPriceFromTick(alm.tickLower()),
                isInvertedPool,
                decimalsDelta
            )
        );
        return SafeCast.toUint128(liquidity.mul(liquidityMultiplier));
    }

    function checkDeviations() internal view {
        uint256 price = oracle.price();
        (uint256 currentCL, uint256 currentCS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();

        uint256 _longLeverage = PRBMath.mulDiv(currentCL, price, currentCL.mul(price) - DL);
        uint256 _shortLeverage = currentCS.div(currentCS - DS.mul(price));

        uint256 deviationLong = ALMMathLib.absSub(_longLeverage, longLeverage);
        uint256 deviationShort = ALMMathLib.absSub(_shortLeverage, shortLeverage);
        require(deviationLong <= maxDeviationLong, "D1");
        require(deviationShort <= maxDeviationShort, "D2");
    }

    // --- Modifiers --- //

    modifier onlyRebalanceOperator() {
        if (msg.sender != rebalanceOperator) revert NotRebalanceOperator();
        _;
    }

    // --- Helpers --- //

    function baseBalanceUnwr() internal view returns (uint256) {
        return base.balanceOf(address(this));
    }

    function quoteBalanceUnwr() internal view returns (uint256) {
        return quote.balanceOf(address(this));
    }
}
