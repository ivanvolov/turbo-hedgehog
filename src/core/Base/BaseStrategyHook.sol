// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

// ** External imports
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {ALMMathLib} from "../../libraries/ALMMathLib.sol";

// ** contracts
import {Base} from "./Base.sol";

// ** interfaces
import {IALM} from "../../interfaces/IALM.sol";

abstract contract BaseStrategyHook is BaseHook, Base, IALM {
    event PausedSet(bool paused);
    event ShutdownSet(bool shutdown);
    event OperatorsSet(address indexed liquidityOperator, address indexed swapOperator);
    event TreasurySet(address indexed treasury);
    event ProtocolParamsSet(
        uint256 protocolFee,
        uint256 tvlCap,
        int24 tickUpperDelta,
        int24 tickLowerDelta,
        uint256 swapPriceThreshold
    );
    event LiquidityUpdated(uint128 newLiquidity);
    event SqrtPriceUpdated(uint160 newSqrtPrice);
    event BoundariesUpdated(int24 newTickLower, int24 newTickUpper);

    using PoolIdLibrary for PoolKey;
    using PRBMathUD60x18 for uint256;

    uint128 public liquidity;
    uint160 public sqrtPriceCurrent;
    int24 public tickLower;
    int24 public tickUpper;

    bool public paused = false;
    bool public shutdown = false;
    int24 public tickUpperDelta;
    int24 public tickLowerDelta;
    bool public immutable isInvertedAssets;
    bool public immutable isInvertedPool;
    uint256 public swapPriceThreshold;
    bytes32 public authorizedPool;
    address public liquidityOperator;
    address public swapOperator;
    uint256 public tvlCap;

    address public treasury;
    uint256 public protocolFee;
    uint256 public accumulatedFeeB;
    uint256 public accumulatedFeeQ;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        bool _isInvertedPool,
        bool _isInvertedAssets,
        IPoolManager _poolManager
    ) BaseHook(_poolManager) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        isInvertedPool = _isInvertedPool;
        isInvertedAssets = _isInvertedAssets;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedSet(_paused);
    }

    function setShutdown(bool _shutdown) external onlyOwner {
        shutdown = _shutdown;
        emit ShutdownSet(_shutdown);
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

    function setProtocolParams(
        uint256 _protocolFee,
        uint256 _tvlCap,
        int24 _tickUpperDelta,
        int24 _tickLowerDelta,
        uint256 _swapPriceThreshold
    ) external onlyOwner {
        protocolFee = _protocolFee;
        tvlCap = _tvlCap;
        tickUpperDelta = _tickUpperDelta;
        tickLowerDelta = _tickLowerDelta;
        swapPriceThreshold = _swapPriceThreshold;
        emit ProtocolParamsSet(_protocolFee, _tvlCap, _tickUpperDelta, _tickLowerDelta, _swapPriceThreshold);
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
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: true,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external view override onlyAuthorizedPool(key) returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function updateBoundaries() external onlyRebalanceAdapter {
        _updateBoundaries();
    }

    function updateLiquidity(uint128 _liquidity) external onlyRebalanceAdapter {
        liquidity = _liquidity;
        emit LiquidityUpdated(_liquidity);
    }

    function updateSqrtPrice(uint160 _sqrtPrice) external onlyRebalanceAdapter {
        sqrtPriceCurrent = _sqrtPrice;
        emit SqrtPriceUpdated(_sqrtPrice);
    }

    function _updateBoundaries() internal {
        int24 tick = ALMMathLib.getTickFromPrice(
            ALMMathLib.getPoolPriceFromOraclePrice(oracle.price(), isInvertedPool, decimalsDelta)
        );
        tickUpper = isInvertedPool ? tick - tickUpperDelta : tick + tickUpperDelta;
        tickLower = isInvertedPool ? tick + tickLowerDelta : tick - tickLowerDelta;

        emit BoundariesUpdated(tickLower, tickUpper);
    }

    // --- Deltas calculation --- //

    function getZeroForOneDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 token0In,
            uint256 token1Out,
            uint160 sqrtPriceNext,
            uint256 fee
        )
    {
        if (amountSpecified > 0) {
            token1Out = uint256(amountSpecified);
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, token1Out);

            token0In = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            fee = token0In.mul(positionManager.getSwapFees(true, amountSpecified));
            token0In += fee;

            beforeSwapDelta = toBeforeSwapDelta(
                -SafeCast.toInt128(token1Out), // specified token = token1
                SafeCast.toInt128(token0In) // unspecified token = token0
            );
        } else {
            unchecked {
                token0In = uint256(-amountSpecified);
            }
            fee = token0In.mul(positionManager.getSwapFees(true, amountSpecified));
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(sqrtPriceCurrent, liquidity, token0In - fee);

            token1Out = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            beforeSwapDelta = toBeforeSwapDelta(
                SafeCast.toInt128(token0In), // specified token = token0
                -SafeCast.toInt128(token1Out) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (
            BeforeSwapDelta beforeSwapDelta,
            uint256 token0Out,
            uint256 token1In,
            uint160 sqrtPriceNext,
            uint256 fee
        )
    {
        if (amountSpecified > 0) {
            token0Out = uint256(amountSpecified);
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, token0Out);

            token1In = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            fee = token1In.mul(positionManager.getSwapFees(false, amountSpecified));
            token1In += fee;

            beforeSwapDelta = toBeforeSwapDelta(
                -SafeCast.toInt128(token0Out), // specified token = token0
                SafeCast.toInt128(token1In) // unspecified token = token1
            );
        } else {
            unchecked {
                token1In = uint256(-amountSpecified);
            }
            fee = token1In.mul(positionManager.getSwapFees(false, amountSpecified));
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(sqrtPriceCurrent, liquidity, token1In - fee);

            token0Out = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            beforeSwapDelta = toBeforeSwapDelta(
                SafeCast.toInt128(token1In), // specified token = token1
                -SafeCast.toInt128(token0Out) // unspecified token = token0
            );
        }
    }

    // --- Modifiers --- //

    /// @dev Only allows execution for the authorized pool
    modifier onlyAuthorizedPool(PoolKey memory poolKey) {
        if (PoolId.unwrap(poolKey.toId()) != authorizedPool) {
            revert UnauthorizedPool();
        }
        _;
    }
}
