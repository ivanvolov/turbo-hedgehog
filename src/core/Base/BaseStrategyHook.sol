// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
// ** contracts
import {Base} from "@src/core/Base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";

abstract contract BaseStrategyHook is BaseHook, Base, IALM {
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
    bool public isInvertAssets;
    bool public isInvertedPool;
    uint256 public swapPriceThreshold;
    bytes32 public authorizedPool;
    address public liquidityOperator;
    address public swapOperator;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) Base(msg.sender) {}

    function setTickUpperDelta(int24 _tickUpperDelta) external onlyOwner {
        tickUpperDelta = _tickUpperDelta;
    }

    function setTickLowerDelta(int24 _tickLowerDelta) external onlyOwner {
        tickLowerDelta = _tickLowerDelta;
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function setShutdown(bool _shutdown) external onlyOwner {
        shutdown = _shutdown;
    }

    function setAuthorizedPool(PoolKey memory authorizedPoolKey) external onlyOwner {
        authorizedPool = PoolId.unwrap(authorizedPoolKey.toId());
    }

    function setIsInvertAssets(bool _isInvertAssets) external onlyOwner {
        isInvertAssets = _isInvertAssets;
    }

    function setIsInvertedPool(bool _isInvertedPool) external onlyOwner {
        isInvertedPool = _isInvertedPool;
    }

    function setSwapPriceThreshold(uint256 _swapPriceThreshold) external onlyOwner {
        swapPriceThreshold = _swapPriceThreshold;
    }

    function setLiquidityOperator(address _liquidityOperator) external onlyOwner {
        liquidityOperator = _liquidityOperator;
    }

    function setSwapOperator(address _swapOperator) external onlyOwner {
        swapOperator = _swapOperator;
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

    function updateBoundaries() public onlyRebalanceAdapter {
        _updateBoundaries();
    }

    function updateLiquidity(uint128 _liquidity) public onlyRebalanceAdapter {
        liquidity = _liquidity;
    }

    function updateSqrtPrice(uint160 _sqrtPrice) public onlyRebalanceAdapter {
        sqrtPriceCurrent = _sqrtPrice;
    }

    function _updateBoundaries() internal {
        int24 tick = ALMMathLib.getTickFromPrice(
            ALMMathLib.getPoolPriceFromOraclePrice(oracle.price(), isInvertedPool, uint8(ALMMathLib.absSub(bDec, qDec)))
        );

        if (isInvertedPool) {
            // @Notice: Here it's inverted due to currencies order
            tickUpper = tick - tickUpperDelta;
            tickLower = tick + tickLowerDelta;
        } else {
            tickUpper = tick + tickUpperDelta;
            tickLower = tick - tickLowerDelta;
        }
    }

    // --- Deltas calculation --- //

    function getZeroForOneDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (BeforeSwapDelta beforeSwapDelta, uint256 token0In, uint256 token1Out, uint160 sqrtPriceNext)
    {
        if (amountSpecified > 0) {
            token1Out = uint256(amountSpecified);
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, token1Out);

            token0In = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            token0In = adjustForFeesUp(token0In, true, amountSpecified);
            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(token1Out)), // specified token = token1
                int128(uint128(token0In)) // unspecified token = token0
            );
        } else {
            token0In = uint256(-amountSpecified);
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(token0In, true, amountSpecified)
            );

            token1Out = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(token0In)), // specified token = token0
                -int128(uint128(token1Out)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    )
        internal
        view
        returns (BeforeSwapDelta beforeSwapDelta, uint256 token0Out, uint256 token1In, uint160 sqrtPriceNext)
    {
        if (amountSpecified > 0) {
            token0Out = uint256(amountSpecified);
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, token0Out);

            token1In = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            token1In = adjustForFeesUp(token1In, false, amountSpecified);
            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(token0Out)), // specified token = token0
                int128(uint128(token1In)) // unspecified token = token1
            );
        } else {
            token1In = uint256(-amountSpecified);
            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(token1In, false, amountSpecified)
            );

            token0Out = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(token1In)), // specified token = token1
                -int128(uint128(token0Out)) // unspecified token = token0
            );
        }
    }

    function adjustForFeesDown(
        uint256 amount,
        bool zeroForOne,
        int256 amountSpecified
    ) public view returns (uint256 amountAdjusted) {
        uint256 fee = positionManager.getSwapFees(zeroForOne, amountSpecified);
        amountAdjusted = amount - amount.mul(fee);
    }

    function adjustForFeesUp(
        uint256 amount,
        bool zeroForOne,
        int256 amountSpecified
    ) public view returns (uint256 amountAdjusted) {
        uint256 fee = positionManager.getSwapFees(zeroForOne, amountSpecified);
        amountAdjusted = amount + amount.mul(fee);
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
