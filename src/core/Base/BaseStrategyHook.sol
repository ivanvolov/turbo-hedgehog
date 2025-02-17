// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** v4 imports
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** contracts
import {Base} from "@src/core/Base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";

abstract contract BaseStrategyHook is BaseHook, Base, IALM {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;

    uint128 public liquidity;
    uint160 public sqrtPriceCurrent;
    int24 public tickLower;
    int24 public tickUpper;

    bool public paused = false;
    bool public shutdown = false;
    int24 public tickDelta = 3000;
    bool public isInvertAssets = false;
    bool public isInvertedPool = true;
    uint256 public swapPriceThreshold;
    bytes32 public authorizedPool;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) Base(msg.sender) {}

    function setTickDelta(int24 _tickDelta) external onlyOwner {
        tickDelta = _tickDelta;
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
        console.log("_updateBoundaries price: %s", oracle.price());
        int24 tick = ALMMathLib.getTickFromPrice(
            ALMMathLib.getPoolPriceFromOraclePrice(oracle.price(), isInvertedPool, uint8(ALMMathLib.absSub(bDec, qDec)))
        );
        console.log("_updateBoundaries tick:");
        console.log(tick);

        if (isInvertedPool) {
            // Here it's inverted due to currencies order
            tickUpper = tick - tickDelta;
            tickLower = tick + tickDelta;
        } else {
            tickUpper = tick + tickDelta;
            tickLower = tick - tickDelta;
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
            // console.log("> amount specified positive");
            token1Out = uint256(amountSpecified);
            console.log("token1Out %s", token1Out);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, token1Out);
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            token0In = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            token0In = adjustForFeesUp(token0In, true, amountSpecified);
            console.log("token0In %s", token0In);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(token1Out)), // specified token = token1
                int128(uint128(token0In)) // unspecified token = token0
            );
        } else {
            // console.log("> amount specified negative");
            token0In = uint256(-amountSpecified);
            console.log("token0In %s", token0In);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(token0In, true, amountSpecified)
            );
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            token1Out = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            console.log("token1Out %s", token1Out);

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
            // console.log("> amount specified positive");
            token0Out = uint256(amountSpecified);
            console.log("token0Out %s", token0Out);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, token0Out);
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            token1In = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            token1In = adjustForFeesUp(token1In, false, amountSpecified);
            console.log("token1In %s", token1In);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(token0Out)), // specified token = token0
                int128(uint128(token1In)) // unspecified token = token1
            );
        } else {
            // console.log("> amount specified negative");
            token1In = uint256(-amountSpecified);
            console.log("token1In %s", token1In);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(
                sqrtPriceCurrent,
                liquidity,
                adjustForFeesDown(token1In, false, amountSpecified)
            );
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            token0Out = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            console.log("token0Out %s", token0Out);

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
        amountAdjusted = amount - (amount * fee) / 1e18;
    }

    function adjustForFeesUp(
        uint256 amount,
        bool zeroForOne,
        int256 amountSpecified
    ) public view returns (uint256 amountAdjusted) {
        uint256 fee = positionManager.getSwapFees(zeroForOne, amountSpecified);
        amountAdjusted = amount + (amount * fee) / 1e18;
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
