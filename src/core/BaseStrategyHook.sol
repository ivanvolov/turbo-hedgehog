// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IWETH} from "@forks/IWETH.sol";
import {IALM} from "@src/interfaces/IALM.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";

abstract contract BaseStrategyHook is BaseHook, IALM {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;

    ILendingAdapter public lendingAdapter;
    address public rebalanceAdapter;

    IWETH WETH = IWETH(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    uint128 public liquidity;
    uint160 public sqrtPriceCurrent;
    int24 public tickLower;
    int24 public tickUpper;

    address public immutable hookDeployer;

    uint256 public almIdCounter = 0;
    mapping(uint256 => ALMInfo) almInfo;

    bool public paused = false;
    bool public shutdown = false;
    int24 public tickDelta = 3000; //TODO: set up production values here

    int256 public k1 = 1e18 / 2; //TODO: set up production values here
    int256 public k2 = 1e18 / 2;
    int256 public k3 = 1e18 / 2;
    int256 public k4 = 1e18 / 2;

    bytes32 public authorizedPool;

    function getALMInfo(uint256 almId) external view returns (ALMInfo memory) {
        return almInfo[almId];
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        hookDeployer = msg.sender;
    }

    function setLendingAdapter(address _lendingAdapter) external onlyHookDeployer {
        if (address(lendingAdapter) != address(0)) {
            WETH.approve(address(lendingAdapter), 0);
            USDC.approve(address(lendingAdapter), 0);
        }
        lendingAdapter = ILendingAdapter(_lendingAdapter);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);
    }

    function setRebalanceAdapter(address _rebalanceAdapter) external onlyHookDeployer {
        rebalanceAdapter = _rebalanceAdapter;
    }

    function setTickDelta(int24 _tickDelta) external onlyHookDeployer {
        tickDelta = _tickDelta;
    }

    function setPaused(bool _paused) external onlyHookDeployer {
        paused = _paused;
    }

    function setShutdown(bool _shutdown) external onlyHookDeployer {
        shutdown = _shutdown;
    }

    function setKParams(int256 _k1, int256 _k2, int256 _k3, int256 _k4) external onlyHookDeployer {
        k1 = _k1;
        k2 = _k2;
        k3 = _k3;
        k4 = _k4;
    }

    function setAuthorizedPool(PoolKey memory authorizedPoolKey) external onlyHookDeployer {
        authorizedPool = PoolId.unwrap(authorizedPoolKey.toId());
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

    function updateBoundaries() public onlyRebalanceAdapter {
        _updateBoundaries();
    }

    function _updateBoundaries() internal {
        int24 tick = ALMMathLib.getTickFromSqrtPrice(sqrtPriceCurrent);
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

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneOut(sqrtPriceCurrent, liquidity, wethOut);

            usdcIn = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(wethOut)), // specified token = token1
                int128(uint128(usdcIn)) // unspecified token = token0
            );
        } else {
            // console.log("> amount specified negative");
            usdcIn = uint256(-amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96ZeroForOneIn(sqrtPriceCurrent, liquidity, usdcIn);

            wethOut = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);

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

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroOut(sqrtPriceCurrent, liquidity, usdcOut);

            wethIn = ALMMathLib.getSwapAmount1(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                -int128(uint128(usdcOut)), // specified token = token0
                int128(uint128(wethIn)) // unspecified token = token1
            );
        } else {
            // console.log("> amount specified negative");
            wethIn = uint256(-amountSpecified);

            sqrtPriceNext = ALMMathLib.sqrtPriceNextX96OneForZeroIn(sqrtPriceCurrent, liquidity, wethIn);

            usdcOut = ALMMathLib.getSwapAmount0(sqrtPriceCurrent, sqrtPriceNext, liquidity);

            beforeSwapDelta = toBeforeSwapDelta(
                int128(uint128(wethIn)), // specified token = token1
                -int128(uint128(usdcOut)) // unspecified token = token0
            );
        }
    }

    // --- Modifiers ---

    /// @dev Only the hook deployer may call this function
    modifier onlyHookDeployer() {
        if (msg.sender != hookDeployer) revert NotHookDeployer();
        _;
    }

    /// @dev Only the rebalance adapter may call this function
    modifier onlyRebalanceAdapter() {
        if (msg.sender != rebalanceAdapter) revert NotRebalanceAdapter();
        _;
    }

    /// @dev Only allows execution when the contract is not paused
    modifier notPaused() {
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
