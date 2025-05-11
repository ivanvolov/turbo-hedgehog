// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";

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
    error ProtocolFeeNotValid();

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

    bool public immutable isInvertedAssets;
    bool public immutable isInvertedPool;
    bytes32 public authorizedPool;

    bool public paused = false;
    bool public shutdown = false;
    address public liquidityOperator;
    address public swapOperator;

    uint128 public liquidity;
    uint160 public sqrtPriceCurrent;
    int24 public tickLower;
    int24 public tickUpper;

    int24 public tickUpperDelta;
    int24 public tickLowerDelta;
    uint256 public swapPriceThreshold;
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
        if (_protocolFee > 1e18) revert ProtocolFeeNotValid();
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
    ) external view override onlyPoolManager onlyAuthorizedPool(key) returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function updateBoundaries(uint160 sqrtPriceAtLastRebalance) external onlyRebalanceAdapter {
        _updateBoundaries(sqrtPriceAtLastRebalance);
    }

    function updateLiquidity(uint128 _liquidity) external onlyRebalanceAdapter {
        liquidity = _liquidity;
        emit LiquidityUpdated(_liquidity);
    }

    function updateSqrtPrice(uint160 _sqrtPrice) external onlyRebalanceAdapter {
        sqrtPriceCurrent = _sqrtPrice;
        emit SqrtPriceUpdated(_sqrtPrice);
    }

    function _updateBoundaries(uint160 sqrtPriceAtLastRebalance) internal {
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceAtLastRebalance);

        console.log("GET TICK FROM PRICE =========== %S", tick);
        tickUpper = isInvertedPool ? tick - tickUpperDelta : tick + tickUpperDelta;
        tickLower = isInvertedPool ? tick + tickLowerDelta : tick - tickLowerDelta;

        emit BoundariesUpdated(tickLower, tickUpper);
    }

    // ** Deltas calculation

    function getDeltas(
        int256 amountSpecified,
        bool zeroForOne
    )
        internal
        view
        returns (BeforeSwapDelta beforeSwapDelta, uint256 tokenIn, uint256 tokenOut, uint160 sqrtPriceNext, uint256 fee)
    {
        if (amountSpecified > 0) {
            console.log("case AS1");
            tokenOut = uint256(amountSpecified);
            sqrtPriceNext = zeroForOne
                ? ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, tokenOut)
                : ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, tokenOut);

            tokenIn = zeroForOne
                ? ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity)
                : ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            fee = tokenIn.mul(positionManager.getSwapFees(zeroForOne, amountSpecified));
            tokenIn += fee;

            beforeSwapDelta = toBeforeSwapDelta(
                -SafeCast.toInt128(tokenOut), // specified token = zeroForOne ? token1 : token0
                SafeCast.toInt128(tokenIn) // unspecified token = zeroForOne ? token0 : token1
            );
        } else {
            console.log("case AS2");
            unchecked {
                tokenIn = uint256(-amountSpecified);
            }
            sqrtPriceNext = zeroForOne
                ? ALMMathLib.sqrtPriceNextX96ZeroForOneIn(sqrtPriceCurrent, liquidity, tokenIn)
                : ALMMathLib.sqrtPriceNextX96OneForZeroIn(sqrtPriceCurrent, liquidity, tokenIn);

            tokenOut = zeroForOne
                ? ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity)
                : ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            fee = tokenOut.mul(positionManager.getSwapFees(zeroForOne, amountSpecified));
            tokenOut -= fee;

            beforeSwapDelta = toBeforeSwapDelta(
                SafeCast.toInt128(tokenIn), // specified token = zeroForOne ? token0 : token1
                -SafeCast.toInt128(tokenOut) // unspecified token = zeroForOne ? token1 : token0
            );
        }
    }

    // ** Modifiers

    /// @dev Only allows execution for the authorized pool
    modifier onlyAuthorizedPool(PoolKey memory poolKey) {
        if (PoolId.unwrap(poolKey.toId()) != authorizedPool) {
            revert UnauthorizedPool();
        }
        _;
    }
}
