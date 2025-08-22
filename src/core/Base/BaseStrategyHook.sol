// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SafeCast as SafeCastLib} from "v4-core/libraries/SafeCast.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

// ** external imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {mulDiv18 as mul18} from "@prb-math/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {ALMMathLib, WAD, div18} from "../../libraries/ALMMathLib.sol";
import {CurrencySettler} from "../../libraries/CurrencySettler.sol";

// ** contracts
import {Base} from "./Base.sol";

// ** interfaces
import {IBaseStrategyHook} from "../../interfaces/IBaseStrategyHook.sol";

/// @title Base Strategy Hook
/// @notice Contract that serves as a hook and handles swap flow.
contract BaseStrategyHook is BaseHook, Base, ReentrancyGuard, IBaseStrategyHook {
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    /// @notice WETH9 address to wrap and unwrap ETH during swaps.
    /// @dev If address is zero, ETH is not supported.
    IWETH9 public immutable WETH9;

    bool public immutable isInvertedPool;
    bytes32 public authorizedPoolId;
    PoolKey public authorizedPoolKey;

    /// @notice The multiplier applied to virtual liquidity, encoded as a UD60x18 value.
    /// @dev A value of 1e18 represents 1.0x (100%), 2e18 represents 2.0x (200%), etc.
    uint256 public liquidityMultiplier;
    uint128 public liquidity;
    Ticks public activeTicks;
    Ticks public tickDeltas;
    uint256 public swapPriceThreshold;
    address public swapOperator;
    address public treasury;
    uint256 public protocolFee;
    uint24 public nextLPFee;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        IWETH9 _WETH9,
        bool _isInvertedPool,
        IPoolManager _poolManager
    ) BaseHook(_poolManager) Base(ComponentType.HOOK, msg.sender, _base, _quote) {
        WETH9 = _WETH9;
        isInvertedPool = _isInvertedPool;
    }

    function setOperator(address _swapOperator) external onlyOwner {
        swapOperator = _swapOperator;
        emit OperatorSet(_swapOperator);
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit TreasurySet(_treasury);
    }

    /// @notice The lp fee is represented in hundredths of a bip, so the max is 100%.
    uint24 internal constant MAX_SWAP_FEE = 1e6;

    function setNextLPFee(uint24 _nextLPFee) external onlyOwner {
        if (_nextLPFee > MAX_SWAP_FEE) revert LPFeeTooLarge(_nextLPFee);
        nextLPFee = _nextLPFee;
    }

    function setProtocolParams(
        uint256 _liquidityMultiplier,
        uint256 _protocolFee,
        int24 _tickLowerDelta,
        int24 _tickUpperDelta,
        uint256 _swapPriceThreshold
    ) external onlyOwner {
        if (_protocolFee > WAD) revert ProtocolFeeNotValid();
        if (_liquidityMultiplier > 10 * WAD) revert LiquidityMultiplierNotValid();
        if (_tickLowerDelta <= 0 || _tickUpperDelta <= 0) revert TickDeltasNotValid();

        liquidityMultiplier = _liquidityMultiplier;
        protocolFee = _protocolFee;
        swapPriceThreshold = _swapPriceThreshold;
        tickDeltas = Ticks(_tickLowerDelta, _tickUpperDelta);

        emit ProtocolParamsSet(
            _liquidityMultiplier,
            _protocolFee,
            _swapPriceThreshold,
            _tickLowerDelta,
            _tickUpperDelta
        );
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function _afterInitialize(
        address creator,
        PoolKey calldata key,
        uint160 sqrtPrice,
        int24
    ) internal override onlyActive returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        if (creator != owner) revert OwnableUnauthorizedAccount(creator);
        if (authorizedPoolId != bytes32("")) revert OnlyOnePoolPerHook();
        authorizedPoolKey = key;
        authorizedPoolId = PoolId.unwrap(key.toId());

        _updatePriceAndBoundaries(sqrtPrice);
        return IHooks.afterInitialize.selector;
    }

    /// @dev Disable adding liquidity through the PM.
    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override onlyAuthorizedPool(key) returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    // ** Swapping logic

    function _beforeSwap(
        address swapper,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override onlyActive onlyAuthorizedPool(key) nonReentrant returns (bytes4, BeforeSwapDelta, uint24) {
        if (swapOperator != address(0) && swapOperator != swapper) revert NotASwapOperator();
        lendingAdapter.syncPositions();

        Ticks memory _activeTicks = activeTicks;
        poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: _activeTicks.lower,
                tickUpper: _activeTicks.upper,
                liquidityDelta: SafeCast.toInt256(liquidity),
                salt: bytes32(0)
            }),
            ""
        );
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(
        address swapper,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override onlyActive onlyAuthorizedPool(key) nonReentrant returns (bytes4, int128) {
        Ticks memory _activeTicks = activeTicks;
        (, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: _activeTicks.lower,
                tickUpper: _activeTicks.upper,
                liquidityDelta: -SafeCast.toInt256(poolManager.getLiquidity(PoolId.wrap(authorizedPoolId))),
                salt: bytes32(0)
            }),
            ""
        );
        uint160 sqrtPrice = sqrtPriceCurrent();
        checkSwapDeviations(sqrtPrice);

        // We assume that fees are positive and only one token accrued fees during a single swap.
        uint128 feesAccrued0 = SafeCastLib.toUint128(feesAccrued.amount0());
        uint128 feesAccrued1 = SafeCastLib.toUint128(feesAccrued.amount1());
        settleDeltas(key, params.zeroForOne, feesAccrued0 + feesAccrued1, sqrtPrice);

        emit HookFee(authorizedPoolId, swapper, feesAccrued0, feesAccrued1);
        return (IHooks.afterSwap.selector, 0);
    }

    function settleDeltas(PoolKey calldata key, bool zeroForOne, uint256 feeAmount, uint160 sqrtPrice) internal {
        if (zeroForOne) {
            uint256 token0 = SafeCast.toUint256(poolManager.currencyDelta(address(this), key.currency0));
            uint256 token1 = SafeCast.toUint256(-poolManager.currencyDelta(address(this), key.currency1));

            key.currency0.take(poolManager, address(this), token0, false);
            if (address(WETH9) != address(0)) WETH9.deposit{value: token0}();
            updatePosition(feeAmount, token0, token1, isInvertedPool, sqrtPrice);
            key.currency1.settle(poolManager, address(this), token1, false);
        } else {
            uint256 token0 = SafeCast.toUint256(-poolManager.currencyDelta(address(this), key.currency0));
            uint256 token1 = SafeCast.toUint256(poolManager.currencyDelta(address(this), key.currency1));

            key.currency1.take(poolManager, address(this), token1, false);
            updatePosition(feeAmount, token1, token0, !isInvertedPool, sqrtPrice);
            if (address(WETH9) != address(0)) WETH9.withdraw(token0);
            key.currency0.settle(poolManager, address(this), token0, false);
        }
    }

    function updatePosition(uint256 feeAmount, uint256 tokenIn, uint256 tokenOut, bool up, uint160 sqrtPrice) internal {
        uint256 protocolFeeAmount = protocolFee == 0 ? 0 : mul18(feeAmount, protocolFee);
        if (up) positionManager.positionAdjustmentPriceUp((tokenIn - protocolFeeAmount), tokenOut, sqrtPrice);
        else positionManager.positionAdjustmentPriceDown(tokenOut, (tokenIn - protocolFeeAmount), sqrtPrice);
    }

    function checkSwapDeviations(uint256 sqrtPriceNext) internal view {
        uint256 sqrtPriceAtLastRebalance = rebalanceAdapter.sqrtPriceAtLastRebalance();
        uint256 priceThreshold = div18(sqrtPriceNext, sqrtPriceAtLastRebalance);
        if (priceThreshold < WAD) priceThreshold = div18(sqrtPriceAtLastRebalance, sqrtPriceNext);
        if (priceThreshold >= swapPriceThreshold) revert SwapPriceChangeTooHigh();
    }

    receive() external payable onlyActive {
        if (address(WETH9) == address(0)) revert NativeTokenUnsupported();
        if (msg.sender != address(WETH9) && msg.sender != address(poolManager)) revert InvalidNativeTokenSender();
    }

    function refreshReservesAndTransferFees() external onlyActive onlyRebalanceAdapter {
        lendingAdapter.syncPositions();
        uint256 accumulatedFeeB = BASE.balanceOf(address(this));
        uint256 accumulatedFeeQ = QUOTE.balanceOf(address(this));

        if (accumulatedFeeB > 0) BASE.safeTransfer(treasury, accumulatedFeeB);
        if (accumulatedFeeQ > 0) QUOTE.safeTransfer(treasury, accumulatedFeeQ);
    }

    /// @notice Updates liquidity and sets new boundaries around the current oracle price.
    function updateLiquidityAndBoundariesToOracle() external override onlyOwner onlyActive {
        (, uint160 oracleSqrtPrice) = oracle.poolPrice();
        _updateLiquidityAndBoundaries(oracleSqrtPrice);
    }

    /// @notice Updates liquidity and sets new boundaries around the specified sqrt price.
    /// @param sqrtPrice The square root price around which the new liquidity boundaries are set.
    /// @return newLiquidity The updated liquidity after recalculation.
    function updateLiquidityAndBoundaries(
        uint160 sqrtPrice
    ) external override onlyRebalanceAdapter onlyActive returns (uint128) {
        return _updateLiquidityAndBoundaries(sqrtPrice);
    }

    /// @notice Recalculates and updates liquidity.
    /// @return newLiquidity The updated liquidity after recalculation.
    function updateLiquidity() external override onlyALM notPaused returns (uint128) {
        return _updateLiquidity();
    }

    function _updateLiquidityAndBoundaries(uint160 sqrtPrice) internal returns (uint128) {
        // Unlocks to enable swap, which updates pool's sqrt price to target.
        poolManager.unlock(abi.encode(sqrtPrice));
        _updatePriceAndBoundaries(sqrtPrice);
        return _updateLiquidity();
    }

    function _updateLiquidity() internal returns (uint128 newLiquidity) {
        newLiquidity = calcLiquidity();
        liquidity = newLiquidity;
        emit LiquidityUpdated(newLiquidity);
    }

    function unlockCallback(bytes calldata data) external onlyPoolManager onlyActive returns (bytes memory) {
        (uint160 sqrtPriceTarget) = abi.decode(data, (uint160));
        uint160 sqrtPrice = sqrtPriceCurrent();
        if (sqrtPriceTarget < sqrtPrice) {
            poolManager.swap(authorizedPoolKey, SwapParams(true, type(int256).min, sqrtPriceTarget), "");
        } else if (sqrtPriceTarget > sqrtPrice) {
            poolManager.swap(authorizedPoolKey, SwapParams(false, type(int128).max, sqrtPriceTarget), "");
        }
        return "";
    }

    function _updatePriceAndBoundaries(uint160 sqrtPrice) internal {
        int24 tick = ALMMathLib.getTickFromSqrtPriceX96(sqrtPrice);

        (, , , uint24 lpFee) = poolManager.getSlot0(PoolId.wrap(authorizedPoolId));
        if (lpFee != nextLPFee) {
            lpFee = nextLPFee;
            poolManager.updateDynamicLPFee(authorizedPoolKey, nextLPFee);
            emit LPFeeSet(nextLPFee);
        }

        Ticks memory deltas = tickDeltas;
        int24 newTickLower = ALMMathLib.alignComputedTickWithTickSpacing(
            tick - deltas.lower,
            authorizedPoolKey.tickSpacing
        );
        int24 newTickUpper = ALMMathLib.alignComputedTickWithTickSpacing(
            tick + deltas.upper,
            authorizedPoolKey.tickSpacing
        );

        if (newTickLower >= newTickUpper) revert TicksMisordered(newTickLower, newTickUpper);
        if (newTickLower < TickMath.MIN_TICK || newTickLower > TickMath.MAX_TICK)
            revert TickLowerOutOfBounds(newTickLower);
        if (newTickUpper < TickMath.MIN_TICK || newTickUpper > TickMath.MAX_TICK)
            revert TickUpperOutOfBounds(newTickUpper);

        activeTicks = Ticks(newTickLower, newTickUpper);
        emit SqrtPriceUpdated(sqrtPrice);
        emit BoundariesUpdated(newTickLower, newTickUpper);
    }

    function sqrtPriceCurrent() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , ) = poolManager.getSlot0(PoolId.wrap(authorizedPoolId));
    }

    function calcLiquidity() internal view returns (uint128) {
        Ticks memory _activeTicks = activeTicks;
        return
            ALMMathLib.getLiquidity(
                isInvertedPool,
                _activeTicks.lower,
                _activeTicks.upper,
                lendingAdapter.getCollateralLong(),
                liquidityMultiplier
            );
    }

    // ** Modifiers

    /// @dev Only allows execution for the authorized pool.
    modifier onlyAuthorizedPool(PoolKey memory poolKey) {
        if (PoolId.unwrap(poolKey.toId()) != authorizedPoolId) {
            revert UnauthorizedPool();
        }
        _;
    }
}
