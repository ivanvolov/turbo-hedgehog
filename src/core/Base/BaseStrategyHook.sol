// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {ALMMathLib, WAD} from "../../libraries/ALMMathLib.sol";

// ** contracts
import {Base} from "./Base.sol";

// ** interfaces
import {IALM} from "../../interfaces/IALM.sol";

/// @title Base Strategy Hook
/// @notice Abstract contract that serves as a base for ALM and holds storage and hook configuration.
abstract contract BaseStrategyHook is BaseHook, Base, IALM {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @notice WETH9 address to wrap and unwrap ETH during swaps.
    /// @dev if address is zero, ETH is not supported.
    IWETH9 public immutable WETH9;

    bool public immutable isInvertedAssets;
    bool public immutable isInvertedPool;
    bytes32 public immutable authorizedPoolId;
    PoolKey public authorizedPoolKey;

    /// @notice Current operational status of the contract.
    /// @dev 0 = active, 1 = paused, 2 = shutdown.
    uint8 public status = 0;

    /// @notice The multiplier applied to the virtual liquidity, encoded as a UD60x18 value.
    ///         (i.e. virtual_liquidity × 1e18, where 1 = 100%).
    uint256 public liquidityMultiplier;
    uint128 public liquidity;

    Ticks public activeTicks;
    Ticks public tickDeltas;
    uint256 public swapPriceThreshold;
    uint256 public tvlCap;

    address public liquidityOperator;
    address public swapOperator;
    address public treasury;
    uint256 public protocolFee;
    uint24 public nextLPFee;
    uint256 public accumulatedFeeB;
    uint256 public accumulatedFeeQ;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        bool _isInvertedPool,
        bool _isInvertedAssets,
        IPoolManager _poolManager
    ) BaseHook(_poolManager) Base(ComponentType.ALM, msg.sender, _base, _quote) {
        isInvertedPool = _isInvertedPool;
        isInvertedAssets = _isInvertedAssets;
    }

    function setStatus(uint8 _status) external onlyOwner {
        status = _status;
        emit StatusSet(_status);
    }

    function setOperators(address _liquidityOperator, address _swapOperator) external onlyOwner {
        liquidityOperator = _liquidityOperator;
        swapOperator = _swapOperator;
        emit OperatorsSet(_liquidityOperator, _swapOperator);
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
        uint256 _tvlCap,
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
        tvlCap = _tvlCap;
        tickDeltas = Ticks(_tickLowerDelta, _tickUpperDelta);

        emit ProtocolParamsSet(
            _liquidityMultiplier,
            _protocolFee,
            _tvlCap,
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

    /// @dev Disable adding liquidity through the PM.
    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal view override onlyAuthorizedPool(key) returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    receive() external payable {
        if (address(WETH9) == address(0)) revert NativeTokenUnsupported();
        if (msg.sender != address(WETH9) && msg.sender != address(poolManager)) revert InvalidNativeTokenSender();
    }

    /// @notice Updates liquidity and sets new boundaries around the current oracle price.
    function updateLiquidityAndBoundariesToOracle() external override onlyOwner onlyActive {
        (, uint160 oracleSqrtPrice) = oracle.poolPrice();
        _updateLiquidityAndBoundaries(oracleSqrtPrice);
    }

    /// @notice Updates liquidity and sets new boundaries around the specified sqrt price.
    /// @param _sqrtPrice The square root price around which the new liquidity boundaries are set.
    /// @return newLiquidity The updated liquidity after recalculation.
    function updateLiquidityAndBoundaries(
        uint160 _sqrtPrice
    ) external override onlyRebalanceAdapter onlyActive returns (uint128) {
        return _updateLiquidityAndBoundaries(_sqrtPrice);
    }

    function _updateLiquidityAndBoundaries(uint160 _sqrtPrice) internal returns (uint128 newLiquidity) {
        // Unlocks to enable the swap, which updates the pool's sqrt price to the target.
        poolManager.unlock(abi.encode(_sqrtPrice));
        _updatePriceAndBoundaries(_sqrtPrice);
        newLiquidity = calcLiquidity();
        liquidity = newLiquidity;
        emit LiquidityUpdated(newLiquidity);
    }

    /// @dev You don't need to reentrancy guard here because PoolManager does it already.
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

    function _updatePriceAndBoundaries(uint160 _sqrtPrice) internal {
        int24 tick = ALMMathLib.getTickFromSqrtPriceX96(_sqrtPrice);

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
        emit SqrtPriceUpdated(_sqrtPrice);
        emit BoundariesUpdated(newTickLower, newTickUpper);
    }

    function sqrtPriceCurrent() public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , ) = poolManager.getSlot0(PoolId.wrap(authorizedPoolId));
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
