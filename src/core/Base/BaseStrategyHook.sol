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
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

// ** libraries
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

// ** contracts
import {Base} from "@src/core/Base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {ILendingPool} from "@src/interfaces/IAave.sol";

abstract contract BaseStrategyHook is BaseHook, Base, IALM {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;

    // AaveV2
    address constant lendingPool = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
    ILendingPool constant LENDING_POOL = ILendingPool(lendingPool);

    uint128 public liquidity;
    uint160 public sqrtPriceCurrent;
    int24 public tickLower;
    int24 public tickUpper;

    bool public paused = false;
    bool public shutdown = false;
    int24 public tickDelta = 3000;
    bool public isInvertAssets = false;

    bytes32 public authorizedPool;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) Base(msg.sender) {}

    function _postSetTokens() internal override {
        IERC20(token0).approve(lendingPool, type(uint256).max);
        IERC20(token1).approve(lendingPool, type(uint256).max);
        IERC20(token0).approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
        IERC20(token1).approve(ALMBaseLib.SWAP_ROUTER, type(uint256).max);
    }

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
        console.log("price: %s", oracle.price());
        int24 tick = ALMMathLib.getTickFromPrice(ALMMathLib.reversePrice(oracle.price()));
        console.log("tick: %s", uint256(int256(tick)));

        // Here it's inverted due to currencies order
        tickUpper = tick - tickDelta;
        tickLower = tick + tickDelta;
    }

    // --- Deltas calculation ---

    function getZeroForOneDeltas(
        int256 amountSpecified
    ) internal view returns (BeforeSwapDelta beforeSwapDelta, uint256 wethOut, uint256 usdcIn, uint160 sqrtPriceNext) {
        if (amountSpecified > 0) {
            // console.log("> amount specified positive");
            wethOut = uint256(amountSpecified);

            console.log("wethOut %s", wethOut);
            console.log("liquidity %s", liquidity);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, wethOut);
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            usdcIn = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            console.log("usdcIn %s", usdcIn);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(wethOut)), // specified token = token1
                int128(uint128(usdcIn)) // unspecified token = token0
            );
        } else {
            // console.log("> amount specified negative");
            usdcIn = uint256(-amountSpecified);

            console.log("usdcIn %s", usdcIn);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(sqrtPriceCurrent, liquidity, usdcIn);
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            wethOut = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            console.log("wethOut %s", wethOut);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(usdcIn)), // specified token = token0
                -int128(uint128(wethOut)) // unspecified token = token1
            );
        }
    }

    function getOneForZeroDeltas(
        int256 amountSpecified
    ) internal view returns (BeforeSwapDelta beforeSwapDelta, uint256 wethIn, uint256 usdcOut, uint160 sqrtPriceNext) {
        if (amountSpecified > 0) {
            // console.log("> amount specified positive");
            usdcOut = uint256(amountSpecified);
            console.log("usdcOut %s", usdcOut);
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, usdcOut);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            wethIn = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);
            console.log("wethIn %s", wethIn);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdcOut)), // specified token = token0
                int128(uint128(wethIn)) // unspecified token = token1
            );
        } else {
            // console.log("> amount specified negative");
            wethIn = uint256(-amountSpecified);
            console.log("wethIn %s", wethIn);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(sqrtPriceCurrent, liquidity, wethIn);
            console.log("sqrtPriceCurrent %s", sqrtPriceCurrent);
            console.log("sqrtPriceNext %s", sqrtPriceNext);

            usdcOut = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(wethIn)), // specified token = token1
                -int128(uint128(usdcOut)) // unspecified token = token0
            );
        }
    }

    // --- Modifiers ---

    /// @dev Only allows execution when the contract is not paused
    modifier notPaused() {
        //TODO: should I stop only hook or all components?
        if (paused) revert ContractPaused();
        _;
    }

    /// @dev Only allows execution when the contract is not shut down
    modifier notShutdown() {
        if (shutdown) revert ContractShutdown();
        _;
    }

    /// @dev Only allows execution for the authorized pool
    modifier onlyAuthorizedPool(PoolKey memory poolKey) {
        if (PoolId.unwrap(poolKey.toId()) != authorizedPool) {
            revert UnauthorizedPool();
        }
        _;
    }
}
