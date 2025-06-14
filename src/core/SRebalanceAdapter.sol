// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18, PRBMath} from "@prb-math/PRBMathUD60x18.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ** libraries
import {ALMMathLib} from "../libraries/ALMMathLib.sol";

// ** contracts
import {Base} from "./base/Base.sol";

// ** interfaces
import {IRebalanceAdapter} from "../interfaces/IRebalanceAdapter.sol";

/// @title Simple Rebalance Adapter
/// @notice Default Rebalance adapter using flash loan and swap adapter to rebalance the position.
contract SRebalanceAdapter is Base, ReentrancyGuard, IRebalanceAdapter {
    error RebalanceConditionNotMet();
    error NotRebalanceOperator();
    error WeightNotValid();
    error LeverageValuesNotValid();
    error MaxDeviationNotValid();
    error DeviationLongExceeded();
    error DeviationShortExceeded();

    /// @notice Emitted when the rebalance is triggered.
    /// @param slippage                The execution slippage, as a UD60x18 value.
    /// @param oraclePriceAtRebalance  The oracle’s price at last rebalance, as a UD60x18 value.
    event Rebalance(
        uint256 indexed priceThreshold,
        uint256 indexed auctionTriggerTime,
        uint256 indexed slippage,
        uint128 liquidity,
        uint256 oraclePriceAtRebalance,
        uint160 sqrtPriceAtRebalance
    );
    event LastRebalanceSnapshotSet(uint256 oraclePrice, uint160 sqrtPrice, uint256 timestamp);
    event RebalanceConstraintsSet(
        uint256 priceThreshold,
        uint256 timeThreshold,
        uint256 maxDevLong,
        uint256 maxDevShort
    );
    event RebalanceParamsSet(uint256 weight, uint256 longLeverage, uint256 shortLeverage);
    event RebalanceOperatorSet(address indexed operator);

    using PRBMathUD60x18 for uint256;

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
        bool _isInvertedPool,
        bool _isInvertedAssets,
        bool _isNova
    ) Base(ComponentType.REBALANCE_ADAPTER, msg.sender, _base, _quote) {
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
        if (_maxDeviationLong > 5e17) revert MaxDeviationNotValid();
        if (_maxDeviationShort > 5e17) revert MaxDeviationNotValid();

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

    function setRebalanceParams(uint256 _weight, uint256 _longLeverage, uint256 _shortLeverage) external onlyOwner {
        if (_weight > WAD) revert WeightNotValid();
        if (_longLeverage > 5 * WAD) revert LeverageValuesNotValid();
        if (_shortLeverage > 5 * WAD) revert LeverageValuesNotValid();
        if (_longLeverage < _shortLeverage) revert LeverageValuesNotValid();

        weight = _weight;
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
        priceThreshold = oraclePrice > oraclePriceAtLastRebalance
            ? oraclePrice.div(oraclePriceAtLastRebalance)
            : oraclePriceAtLastRebalance.div(oraclePrice);
        needRebalance = priceThreshold >= rebalancePriceThreshold;
    }

    /// @notice Computes when the next time‐based rebalance can be triggered
    /// @return needRebalance  True if rebalance is allowed, false otherwise
    /// @return triggerTime    The exact timestamp when a time-based rebalance is allowed
    function isTimeRebalance() public view returns (bool needRebalance, uint256 triggerTime) {
        triggerTime = timeAtLastRebalance + rebalanceTimeThreshold;
        needRebalance = block.timestamp >= triggerTime;
    }

    function rebalance(uint256 slippage) external onlyActive onlyRebalanceOperator nonReentrant {
        (bool isRebalance, uint256 priceThreshold, uint256 auctionTriggerTime) = isRebalanceNeeded();
        if (!isRebalance) revert RebalanceConditionNotMet();
        alm.refreshReservesAndTransferFees();

        (uint256 baseToFl, uint256 quoteToFl, bytes memory data) = _rebalanceCalculations(WAD + slippage);

        if (isNova) {
            if (quoteToFl != 0) flashLoanAdapter.flashLoanSingle(false, quoteToFl, data);
            else flashLoanAdapter.flashLoanSingle(true, baseToFl, data);
            uint256 baseBalance = baseBalanceUnwr();
            if (baseBalance != 0) lendingAdapter.addCollateralShort(baseBalance);
            uint256 quoteBalance = quoteBalanceUnwr();
            if (quoteBalance != 0) lendingAdapter.addCollateralLong(quoteBalance);
        } else {
            flashLoanAdapter.flashLoanTwoTokens(baseToFl, quoteToFl, data);
            uint256 baseBalance = baseBalanceUnwr();
            if (baseBalance != 0) lendingAdapter.repayLong(baseBalance);
            uint256 quoteBalance = quoteBalanceUnwr();
            if (quoteBalance != 0) lendingAdapter.repayShort(quoteBalance);
        }

        // ** Check max deviation
        (uint256 currentPrice, uint256 currentPoolPrice) = oracle.poolPrice();
        checkDeviations(currentPrice);

        // ** Update state
        uint160 currentSqrtPrice = ALMMathLib.getSqrtPriceX96FromPrice(currentPoolPrice);
        oraclePriceAtLastRebalance = currentPrice;
        sqrtPriceAtLastRebalance = currentSqrtPrice;
        timeAtLastRebalance = block.timestamp;

        uint128 liquidity = alm.updateLiquidityAndBoundaries(currentSqrtPrice);
        emit Rebalance(priceThreshold, auctionTriggerTime, slippage, liquidity, currentPrice, currentSqrtPrice);
    }

    function onFlashLoanSingle(
        bool isBase,
        uint256 amount,
        bytes calldata data
    ) external onlyActive onlyFlashLoanAdapter {
        _managePositionDeltas(data);
        uint256 balance = isBase ? baseBalanceUnwr() : quoteBalanceUnwr();
        if (amount > balance) swapAdapter.swapExactOutput(!isBase, amount - balance);
    }

    function onFlashLoanTwoTokens(
        uint256 amountBase,
        uint256 amountQuote,
        bytes calldata data
    ) external onlyActive onlyFlashLoanAdapter {
        _managePositionDeltas(data);

        uint256 baseBalance = BASE.balanceOf(address(this));
        if (amountBase > baseBalance) swapAdapter.swapExactOutput(false, amountBase - baseBalance);
        else {
            uint256 quoteBalance = QUOTE.balanceOf(address(this));
            if (amountQuote > quoteBalance) swapAdapter.swapExactOutput(true, amountQuote - quoteBalance);
        }
    }

    /// @dev This function is mainly for removing stack too deep error.
    function _managePositionDeltas(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS) = abi.decode(
            data,
            (int256, int256, int256, int256)
        );
        lendingAdapter.updatePosition(-deltaCL, -deltaCS, deltaDL, deltaDS);
    }

    // ** Math functions

    uint256 constant WAD = 1e18;

    /// @dev This function is mainly for removing stack too deep error.
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
                targetCS = TVL.mul(WAD - weight).mul(shortLeverage);
            } else {
                targetCL = TVL.mul(weight).mul(longLeverage);
                targetCS = TVL.mul(WAD - weight).mul(shortLeverage).mul(price);
            }

            targetDL = targetCL.mul(price).mul(WAD - WAD.div(longLeverage));
            targetDS = PRBMath.mulDiv(targetCS, WAD - WAD.div(shortLeverage), price);

            if (isNova) {
                // Discount to cover slippage
                targetCL = targetCL.mul(2 * WAD - k);
                targetCS = targetCS.mul(2 * WAD - k);

                // No debt operations in unicord
                targetDL = 0;
                targetDS = 0;
            } else {
                // Borrow additional funds to cover slippage
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

    function checkDeviations(uint256 price) internal view {
        (uint256 currentCL, uint256 currentCS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        (uint256 lLeverage, uint256 sLeverage) = ALMMathLib.getLeverages(price, currentCL, currentCS, DL, DS);

        if (ALMMathLib.absSub(lLeverage, longLeverage) > maxDeviationLong) revert DeviationLongExceeded();
        if (ALMMathLib.absSub(sLeverage, shortLeverage) > maxDeviationShort) revert DeviationShortExceeded();
    }

    // ** Modifiers

    modifier onlyRebalanceOperator() {
        if (msg.sender != rebalanceOperator) revert NotRebalanceOperator();
        _;
    }

    // ** Helpers

    function baseBalanceUnwr() internal view returns (uint256) {
        return BASE.balanceOf(address(this));
    }

    function quoteBalanceUnwr() internal view returns (uint256) {
        return QUOTE.balanceOf(address(this));
    }
}
