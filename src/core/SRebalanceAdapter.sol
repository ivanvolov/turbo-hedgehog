// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** external imports
import {mulDiv, mulDiv18 as mul18} from "@prb-math/Common.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ** contracts
import {Base} from "./base/Base.sol";

// ** libraries
import {ALMMathLib, div18, absSub, WAD} from "../libraries/ALMMathLib.sol";

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
    /// @param slippage The execution slippage, as a UD60x18 value.
    /// @param oraclePriceAtRebalance The oracle’s price at last rebalance, as a UD60x18 value.
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

    // ** Last rebalance snapshot
    uint160 public sqrtPriceAtLastRebalance;
    uint256 public oraclePriceAtLastRebalance;
    uint256 public timeAtLastRebalance;

    // ** Parameters
    /// @notice The target portfolio weight for long vs short positions, encoded as a UD60x18 value.
    /// @dev A value of 0.5e18 represents 50%, 1e18 represents 100%, etc.
    uint256 public weight;

    /// @notice The leverage multiplier applied to long positions, encoded as a UD60x18 value.
    /// @dev A value of 1e18 represents 1x leverage, 2e18 represents 2x leverage, etc.
    uint256 public longLeverage;

    /// @notice The leverage multiplier applied to short positions, encoded as a UD60x18 value.
    /// @dev A value of 1e18 represents 1x leverage, 2e18 represents 2x leverage, etc.
    uint256 public shortLeverage;

    uint256 public rebalancePriceThreshold;
    uint256 public rebalanceTimeThreshold;
    uint256 public maxDeviationLong;
    uint256 public maxDeviationShort;
    bool public immutable isInvertedAssets;
    bool public immutable isNova;
    bool public isQuickRebalance = false;
    address public rebalanceOperator;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        bool _isInvertedAssets,
        bool _isNova
    ) Base(ComponentType.REBALANCE_ADAPTER, msg.sender, _base, _quote) {
        isInvertedAssets = _isInvertedAssets;
        isNova = _isNova;
    }

    function setIsQuickRebalance(bool _isQuickRebalance) external onlyOwner {
        isQuickRebalance = _isQuickRebalance;
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
        if (_longLeverage > 5 * WAD || _longLeverage < WAD) revert LeverageValuesNotValid();
        if (_shortLeverage > 5 * WAD || _shortLeverage < WAD) revert LeverageValuesNotValid();
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

    /// @notice Computes if the next rebalance can be triggered.
    /// @param oraclePrice The current oracle price.
    /// @return needRebalance True if rebalance is allowed, false otherwise.
    /// @return priceThreshold The current price threshold for the price-based rebalance.
    /// @return triggerTime The exact timestamp when a time-based rebalance can be triggered.
    function isRebalanceNeeded(uint256 oraclePrice) public view returns (bool, uint256, uint256) {
        (bool _isPriceRebalance, uint256 priceThreshold) = isPriceRebalance(oraclePrice);
        (bool _isTimeRebalance, uint256 triggerTime) = isTimeRebalance();
        return (_isPriceRebalance || _isTimeRebalance, priceThreshold, triggerTime);
    }

    /// @notice Computes if the next price‐based rebalance can be triggered.
    /// @param oraclePrice The current oracle price.
    /// @return needRebalance True if rebalance is allowed, false otherwise.
    /// @return priceThreshold The current price threshold for the price-based rebalance.
    function isPriceRebalance(uint256 oraclePrice) public view returns (bool needRebalance, uint256 priceThreshold) {
        priceThreshold = oraclePrice > oraclePriceAtLastRebalance
            ? div18(oraclePrice, oraclePriceAtLastRebalance)
            : div18(oraclePriceAtLastRebalance, oraclePrice);
        needRebalance = priceThreshold >= rebalancePriceThreshold;
    }

    /// @notice Computes when the next time‐based rebalance can be triggered.
    /// @return needRebalance True if rebalance is allowed, false otherwise.
    /// @return triggerTime The exact timestamp when a time-based rebalance can be triggered.
    function isTimeRebalance() public view returns (bool needRebalance, uint256 triggerTime) {
        triggerTime = timeAtLastRebalance + rebalanceTimeThreshold;
        needRebalance = block.timestamp >= triggerTime;
    }

    function rebalance(uint256 slippage) external onlyActive onlyRebalanceOperator nonReentrant {
        (uint256 currentPrice, uint160 currentSqrtPrice) = oracle.poolPrice();
        (bool isRebalance, uint256 priceThreshold, uint256 auctionTriggerTime) = isRebalanceNeeded(currentPrice);
        if (!isRebalance) revert RebalanceConditionNotMet();
        hook.refreshReservesAndTransferFees();

        (uint256 baseToFl, uint256 quoteToFl, bytes memory data) = calcFlashLoanParams(WAD + slippage, currentPrice);

        if (isQuickRebalance) {
            if (baseToFl == 0 && quoteToFl == 0) {
                timeAtLastRebalance = block.timestamp;
                return;
            }
        }

        if (isNova) {
            if (quoteToFl != 0) flashLoanAdapter.flashLoanSingle(false, quoteToFl, data);
            else flashLoanAdapter.flashLoanSingle(true, baseToFl, data);
            uint256 balanceBase = getBalanceBase();
            if (balanceBase != 0) lendingAdapter.addCollateralShort(balanceBase);
            uint256 balanceQuote = getBalanceQuote();
            if (balanceQuote != 0) lendingAdapter.addCollateralLong(balanceQuote);
        } else {
            // TODO: this is second approach of foxing the problem
            // if (quoteToFl == 0) flashLoanAdapter.flashLoanSingle(true, baseToFl, data);
            // else if (baseToFl == 0) flashLoanAdapter.flashLoanSingle(false, quoteToFl, data);
            // else flashLoanAdapter.flashLoanTwoTokens(baseToFl, quoteToFl, data);
            flashLoanAdapter.flashLoanTwoTokens(baseToFl, quoteToFl, data);
            uint256 balanceBase = getBalanceBase();
            if (balanceBase != 0) lendingAdapter.repayLong(balanceBase);
            uint256 balanceQuote = getBalanceQuote();
            if (balanceQuote != 0) lendingAdapter.repayShort(balanceQuote);
        }

        // Check max deviation
        checkDeviations(currentPrice);

        // Update state
        oraclePriceAtLastRebalance = currentPrice;
        sqrtPriceAtLastRebalance = currentSqrtPrice;
        timeAtLastRebalance = block.timestamp;

        uint128 liquidity = hook.updateLiquidityAndBoundaries(currentSqrtPrice);
        emit Rebalance(priceThreshold, auctionTriggerTime, slippage, liquidity, currentPrice, currentSqrtPrice);
    }

    function onFlashLoanSingle(
        bool isBase,
        uint256 amount,
        bytes calldata data
    ) external onlyActive onlyFlashLoanAdapter {
        managePositionDeltas(data);
        uint256 balance = isBase ? getBalanceBase() : getBalanceQuote();
        if (amount > balance) swapAdapter.swapExactOutput(!isBase, amount - balance);
    }

    function onFlashLoanTwoTokens(
        uint256 amountBase,
        uint256 amountQuote,
        bytes calldata data
    ) external onlyActive onlyFlashLoanAdapter {
        managePositionDeltas(data);

        uint256 balanceBase = getBalanceBase();
        if (amountBase > balanceBase) swapAdapter.swapExactOutput(false, amountBase - balanceBase);
        else {
            uint256 balanceQuote = getBalanceQuote();
            if (amountQuote > balanceQuote) swapAdapter.swapExactOutput(true, amountQuote - balanceQuote);
        }
    }

    function managePositionDeltas(bytes calldata data) internal {
        (int256 deltaCL, int256 deltaCS, int256 deltaDL, int256 deltaDS) = abi.decode(
            data,
            (int256, int256, int256, int256)
        );
        lendingAdapter.updatePosition(-deltaCL, -deltaCS, deltaDL, deltaDS);
    }

    // ** Math functions

    function calcFlashLoanParams(
        uint256 k,
        uint256 price
    ) internal view returns (uint256 baseToFl, uint256 quoteToFl, bytes memory data) {
        int256 deltaCL;
        int256 deltaCS;
        int256 deltaDL;
        int256 deltaDS;
        {
            (uint256 targetCL, uint256 targetCS, uint256 targetDL, uint256 targetDS) = calculateTargets(price);
            if (isNova) {
                // Discount to cover slippage.
                targetCL = mul18(targetCL, 2 * WAD - k);
                targetCS = mul18(targetCS, 2 * WAD - k);

                // No debt operations in unicord.
                targetDL = 0;
                targetDS = 0;
            } else {
                // Borrow additional funds to cover slippage.
                targetDL = mul18(targetDL, k);
                targetDS = mul18(targetDS, k);
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

    function calculateTargets(
        uint256 price
    ) internal view returns (uint256 targetCL, uint256 targetCS, uint256 targetDL, uint256 targetDS) {
        uint256 TVL = alm.TVL(price);
        if (isInvertedAssets) {
            targetCL = mulDiv(mul18(TVL, weight), longLeverage, price);
            targetCS = mul18(mul18(TVL, WAD - weight), shortLeverage);
        } else {
            targetCL = mul18(TVL, mul18(weight, longLeverage));
            targetCS = mul18(mul18(mul18(TVL, WAD - weight), shortLeverage), price);
        }
        targetDL = mul18(targetCL, mul18(price, WAD - div18(WAD, longLeverage)));
        targetDS = mulDiv(targetCS, WAD - div18(WAD, shortLeverage), price);
    }

    function checkDeviations(uint256 price) internal view {
        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        (uint256 lLeverage, uint256 sLeverage) = ALMMathLib.getLeverages(price, CL, CS, DL, DS);

        if (absSub(lLeverage, longLeverage) > maxDeviationLong) revert DeviationLongExceeded();
        if (absSub(sLeverage, shortLeverage) > maxDeviationShort) revert DeviationShortExceeded();
    }

    // ** Modifiers

    modifier onlyRebalanceOperator() {
        if (msg.sender != rebalanceOperator) revert NotRebalanceOperator();
        _;
    }

    // ** Helpers

    function getBalanceBase() internal view returns (uint256) {
        return BASE.balanceOf(address(this));
    }

    function getBalanceQuote() internal view returns (uint256) {
        return QUOTE.balanceOf(address(this));
    }
}
