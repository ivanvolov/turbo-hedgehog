// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** V4 imports
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolSwapTest} from "@test/libraries/v4-forks/PoolSwapTest.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {IV4Quoter} from "v4-periphery/src/interfaces/IV4Quoter.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {Commands} from "@universal-router/Commands.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";

// ** contracts
import {TestBaseAsserts} from "@test/core/common/TestBaseAsserts.sol";
import {UniswapSwapAdapter} from "@src/core/swapAdapters/UniswapSwapAdapter.sol";
import {Oracle} from "@src/core/oracles/Oracle.sol";
import {ALM} from "@src/ALM.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PRBMathUD60x18} from "@test/libraries/math/PRBMathUD60x18.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TestLib} from "@test/libraries/TestLib.sol";
import {Constants as MConstants} from "@test/libraries/constants/MainnetConstants.sol";

// ** interfaces
import {IOracle} from "@src/interfaces/IOracle.sol";
import {IUniswapSwapAdapter} from "@src/interfaces/swapAdapters/IUniswapSwapAdapter.sol";
import {ISwapRouter} from "@uniswap-v3/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap-v3/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

abstract contract TestBaseUniswap is TestBaseAsserts {
    using PRBMathUD60x18 for uint256;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function setSwapAdapterToV3SingleSwap(address pool) internal {
        IUniswapSwapAdapter(address(swapAdapter)).setRoutesOperator(deployer.addr);

        uint256 fee = IUniswapV3Pool(pool).fee();

        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(
            0,
            protToC(ProtId.V3),
            abi.encodePacked(BASE, uint24(fee), QUOTE)
        );
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(
            1,
            protToC(ProtId.V3),
            abi.encodePacked(QUOTE, uint24(fee), BASE)
        );

        uint256[] memory activeSwapRoute = new uint256[](1);
        activeSwapRoute[0] = 0;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, true, activeSwapRoute);
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, false, activeSwapRoute);

        activeSwapRoute[0] = 1;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, true, activeSwapRoute);
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, false, activeSwapRoute);
    }

    function setSwapAdapterToV4SingleSwap(PoolKey memory targetKey, bool isReversed) internal {
        IUniswapSwapAdapter(address(swapAdapter)).setRoutesOperator(deployer.addr);

        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(
            0,
            protToC(ProtId.V4_SINGLE),
            abi.encode(false, targetKey, true, bytes(""))
        );
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(
            1,
            protToC(ProtId.V4_SINGLE),
            abi.encode(false, targetKey, false, bytes(""))
        );

        uint256[] memory activeSwapRoute = new uint256[](1);
        activeSwapRoute[0] = isReversed ? 1 : 0;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, true, activeSwapRoute); // exactIn, base => quote
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, false, activeSwapRoute); // exactOut, quote => base

        activeSwapRoute[0] = isReversed ? 0 : 1;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, true, activeSwapRoute); // exactOut, base => quote
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, false, activeSwapRoute); // exactIn, quote => base
    }

    function setSwapAdapterToV4MultihopSwap(bytes memory path, bool isReversed) internal {
        IUniswapSwapAdapter(address(swapAdapter)).setRoutesOperator(deployer.addr);

        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(0, protToC(ProtId.V4_MULTIHOP), path);
        IUniswapSwapAdapter(address(swapAdapter)).setSwapPath(1, protToC(ProtId.V4_MULTIHOP), path);

        uint256[] memory activeSwapRoute = new uint256[](1);
        activeSwapRoute[0] = isReversed ? 1 : 0;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, true, activeSwapRoute); // exactIn, base => quote
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, false, activeSwapRoute); // exactOut, quote => base

        activeSwapRoute[0] = isReversed ? 0 : 1;
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(false, true, activeSwapRoute); // exactOut, base => quote
        IUniswapSwapAdapter(address(swapAdapter)).setSwapRoute(true, false, activeSwapRoute); // exactIn, quote => base
    }

    enum ProtId {
        V2,
        V3,
        V4_SINGLE,
        V4_MULTIHOP
    }

    function protToC(ProtId protocolId) internal pure returns (uint8) {
        if (protocolId == ProtId.V2) return 0;
        else if (protocolId == ProtId.V3) return 1;
        else if (protocolId == ProtId.V4_SINGLE) return 2;
        else if (protocolId == ProtId.V4_MULTIHOP) return 3;
        else revert("ProtId not found");
    }

    function _getAndCheckPoolKey(
        IERC20 token0,
        IERC20 token1,
        uint24 fee,
        int24 tickSpacing,
        bytes32 _poolId
    ) internal pure returns (PoolKey memory poolKey) {
        _test_currencies_order(address(token0), address(token1));
        poolKey = PoolKey(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            fee,
            tickSpacing,
            IHooks(address(0))
        );
        PoolId id = poolKey.toId();
        assertEq(PoolId.unwrap(id), _poolId, "PoolId not equal");
    }

    function getTokensInOrder() internal view returns (address, address) {
        return !isInvertedPool ? (address(QUOTE), address(BASE)) : (address(BASE), address(QUOTE));
    }

    // --- Uniswap V3 --- //

    function alignOraclesAndPools(uint160 newSqrtPrice) public {
        alignOracles(newSqrtPrice);
        setV3PoolPrice(newSqrtPrice);
    }

    function alignOraclesAndPoolsV4(ALM _hook, PoolKey memory _poolKey) public {
        // uint256 sqrPriceBefore = _hook.sqrtPriceCurrent();
        // console.log("sqrtPriceBefore %s", sqrPriceBefore);
        // uint160 newSqrtPrice = getV4PoolSQRTPrice(_poolKey);
        // console.log("newSqrtPrice");
        // console.log(newSqrtPrice);
        alignOracles(_hook.sqrtPriceCurrent());
    }

    function alignOracles(uint160 newSqrtPrice) public {
        uint256 _poolPrice = TestLib.getPriceFromSqrtPriceX96(newSqrtPrice);

        uint256 _oraclePrice = TestLib.getOraclePriceFromPoolPrice(_poolPrice, isInvertedPool, int8(bDec) - int8(qDec));
        uint256 ratio = 10 ** uint256(int256(int8(bDec) - int8(qDec)) + 18);
        uint256 _price = _oraclePrice.mul(ratio);

        vm.mockCall(address(oracle), abi.encodeWithSelector(IOracle.price.selector), abi.encode(_price));
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(IOracle.poolPrice.selector),
            abi.encode(_price, _poolPrice)
        );
    }

    function getHookPrice() public view returns (uint256) {
        return _sqrtPriceToOraclePrice(hook.sqrtPriceCurrent());
    }

    function getV3PoolPrice(address pool) public view returns (uint256) {
        return _sqrtPriceToOraclePrice(getV3PoolSQRTPrice(pool));
    }

    function getV4PoolPrice(PoolKey memory _poolKey) public view returns (uint256) {}

    function getV3PoolSQRTPrice(address pool) public view returns (uint160) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96;
    }

    function getV4PoolSQRTPrice(PoolKey memory _poolKey) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96, , , ) = manager.getSlot0(_poolKey.toId());
    }

    function getV3PoolTick(address pool) public view returns (int24) {
        (, int24 tick, , , , , ) = IUniswapV3Pool(pool).slot0();
        return tick;
    }

    function _sqrtPriceToOraclePrice(uint160 sqrtPriceX96) internal view returns (uint256) {
        return
            TestLib.getOraclePriceFromPoolPrice(
                TestLib.getPriceFromSqrtPriceX96(sqrtPriceX96),
                isInvertedPool,
                int8(bDec) - int8(qDec)
            );
    }

    uint256 minStepSize = 10 ether; // Minimum swap amount to prevent tiny swaps
    uint256 slippageTolerance = 1e16; // 1% acceptable price difference

    function _setV3PoolPrice(uint160 newSqrtPrice) public {
        uint256 targetPrice = _sqrtPriceToOraclePrice(newSqrtPrice);

        // ** Configuration parameters
        uint256 initialStepSize = 10 ether; // Initial swap amount
        uint256 adaptiveDecayBase = 90; // 90% decay when moving in right direction
        uint256 aggressiveDecayBase = 70; // 70% decay when overshooting

        uint256 currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
        uint256 previousPrice = currentPrice;
        uint256 stepSize = initialStepSize;

        uint256 iterations = 0;
        while (iterations < 100) {
            uint256 priceDiff = ALMMathLib.absSub(currentPrice, targetPrice);
            if (priceDiff <= slippageTolerance) break;
            iterations++;

            bool isZeroForOne = currentPrice >= targetPrice;
            if (isInvertedPool) isZeroForOne = !isZeroForOne;
            uint256 swapAmount = stepSize;
            if ((isZeroForOne && isInvertedPool) || (!isZeroForOne && !isInvertedPool))
                swapAmount = (stepSize * currentPrice) / 1e30;

            _doV3InputSwap(isZeroForOne, swapAmount);

            // Get new price and calculate improvement
            previousPrice = currentPrice;
            currentPrice = getV3PoolPrice(TARGET_SWAP_POOL);
            uint256 newPriceDiff = ALMMathLib.absSub(currentPrice, targetPrice);

            // Adaptive step size adjustment
            if (newPriceDiff < priceDiff) {
                stepSize = (stepSize * adaptiveDecayBase) / 100; // Moving in right direction
            } else {
                stepSize = (stepSize * aggressiveDecayBase) / 100; // Overshot or wrong direction
            }

            // Ensure minimum step size
            if (stepSize < minStepSize) stepSize = minStepSize;
        }

        // console.log("Final price adjustment results:");
        // console.log("Target price:", targetPrice);
        // console.log("Final price:", currentPrice);
        // console.log("Iterations:", iterations);

        if (ALMMathLib.absSub(currentPrice, targetPrice) > slippageTolerance) revert("setV3PoolPrice fail");
    }

    uint256 constant MAX_ITER = 80; // binary-search depth
    uint256 constant MIN_IN = 3e9; // 3000 USDC   (token1)  or 0.000003 WETH (token0)

    function setV3PoolPrice(uint160 targetSqrtPriceX96) public {
        uint160 sqrtCurrent = hook.sqrtPriceCurrent();
        if (sqrtCurrent == targetSqrtPriceX96) return;

        // ── 0. quick exit if already in band ────────────────────────────────
        uint256 priceTarget = _sqrtPriceToOraclePrice(targetSqrtPriceX96); // 1e18 scale
        uint256 priceCurrent = _sqrtPriceToOraclePrice(sqrtCurrent);
        if (ALMMathLib.absSub(priceTarget, priceCurrent) <= slippageTolerance) return;

        // ── 1. direction + liquidity snapshot ──────────────────────────────
        bool zeroForOne = priceCurrent > priceTarget; // pool price must drop
        if (isInvertedPool) zeroForOne = !zeroForOne; // flip when quoting inverted
        uint128 L = hook.liquidity();

        // Use binary search on the delta-amount rather than on price itself:
        // upper = “enough to overshoot”, lower = 0.  Each step halves the gap.
        uint256 hi;
        uint256 lo = 0;

        // upper bound:  move **whole** way in one go (worst case)
        if (zeroForOne) {
            // token0 in
            hi = SqrtPriceMath.getAmount0Delta(targetSqrtPriceX96, sqrtCurrent, L, true);
        } else {
            // token1 in
            hi = SqrtPriceMath.getAmount1Delta(sqrtCurrent, targetSqrtPriceX96, L, true);
        }

        if (hi < MIN_IN) hi = MIN_IN;

        // ── 2. iterative refinement ( ≤ 8 swaps ) ──────────────────────────
        for (uint8 i; i < MAX_ITER; ++i) {
            uint256 mid = (hi + lo) >> 1; // round-down
            if (mid < MIN_IN) mid = MIN_IN;

            // do the trial swap
            _doV3InputSwap(zeroForOne, mid);

            // compute new price
            sqrtCurrent = hook.sqrtPriceCurrent();
            priceCurrent = _sqrtPriceToOraclePrice(sqrtCurrent);

            // good enough?
            uint256 diff = ALMMathLib.absSub(priceCurrent, priceTarget);
            if (diff <= slippageTolerance) return;

            bool nowAbove = priceCurrent > priceTarget;
            if (nowAbove == (isInvertedPool ? !zeroForOne : zeroForOne)) {
                // we are still on the start side – need more input
                lo = mid;
            } else {
                // we overshot – mid was too large
                hi = mid;
            }
        }

        revert("setV3PoolPrice: cannot converge");
    }

    function _doV3InputSwap(bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        (address _token0, address _token1) = getTokensInOrder();
        deal(zeroForOne ? _token0 : _token1, address(marketMaker.addr), amountIn);
        vm.startPrank(marketMaker.addr);
        amountOut = MConstants.UNISWAP_V3_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: zeroForOne ? _token0 : _token1,
                tokenOut: zeroForOne ? _token1 : _token0,
                fee: getFeeFromV3Pool(TARGET_SWAP_POOL),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    function getFeeFromV3Pool(address pool) public view returns (uint24) {
        return IUniswapV3Pool(pool).fee();
    }

    // --- Uniswap V4 --- //

    function _quoteOutputSwap(bool zeroForOne, uint256 amount) internal returns (uint256 amountIn) {
        (amountIn, ) = quoter.quoteExactOutputSingle(
            IV4Quoter.QuoteExactSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                exactAmount: SafeCast.toUint128(amount),
                hookData: ""
            })
        );
    }

    function _swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (uint256, uint256) {
        (int256 delta0, int256 delta1) = __swap(zeroForOne, amount, _key);
        return (abs(delta0), abs(delta1));
    }

    function __swap(bool zeroForOne, int256 amount, PoolKey memory _key) internal returns (int256, int256) {
        (address _token0, address _token1) = getTokensInOrder();
        uint256 token0Before = IERC20(_token0).balanceOf(swapper.addr);
        uint256 token1Before = IERC20(_token1).balanceOf(swapper.addr);

        vm.startPrank(swapper.addr);
        BalanceDelta delta = swapRouter.swap(
            _key,
            SwapParams(
                zeroForOne,
                amount,
                zeroForOne == true ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            ),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.stopPrank();
        if (zeroForOne) {
            assertEq(token0Before - IERC20(_token0).balanceOf(swapper.addr), abs(delta.amount0()));
            assertEq(IERC20(_token1).balanceOf(swapper.addr) - token1Before, abs(delta.amount1()));
        } else {
            assertEq(IERC20(_token0).balanceOf(swapper.addr) - token0Before, abs(delta.amount0()));
            assertEq(token1Before - IERC20(_token1).balanceOf(swapper.addr), abs(delta.amount1()));
        }
        return (int256(delta.amount0()), int256(delta.amount1()));
    }

    function __swap_production(
        bool zeroForOne,
        bool isExactInput,
        uint256 amount,
        PoolKey memory _key,
        bool isEth
    ) internal {
        vm.startPrank(swapper.addr);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = __getV4Input(_key, zeroForOne, isExactInput, amount);
        bytes memory swapCommands;
        swapCommands = bytes.concat(swapCommands, bytes(abi.encodePacked(uint8(Commands.V4_SWAP))));
        if (isEth) universalRouter.execute{value: amount}(swapCommands, inputs, block.timestamp);
        else universalRouter.execute(swapCommands, inputs, block.timestamp);

        console.log("(10)");

        vm.stopPrank();
    }

    function __getV4Input(
        PoolKey memory poolKey,
        bool zeroForOne,
        bool isExactInput,
        uint256 amount
    ) internal pure returns (bytes memory) {
        bytes[] memory params = new bytes[](3);
        uint8 swapAction = isExactInput ? uint8(Actions.SWAP_EXACT_IN_SINGLE) : uint8(Actions.SWAP_EXACT_OUT_SINGLE);

        params[0] = abi.encode(
            // We use ExactInputSingleParams structure for both exact input and output swaps
            // since the parameter structure is identical.
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: zeroForOne,
                amountIn: uint128(amount),
                amountOutMinimum: isExactInput ? uint128(0) : type(uint128).max,
                hookData: ""
            })
        );

        params[1] = abi.encode(
            zeroForOne ? poolKey.currency0 : poolKey.currency1,
            isExactInput ? amount : type(uint256).max
        );
        params[2] = abi.encode(zeroForOne ? poolKey.currency1 : poolKey.currency0, isExactInput ? 0 : amount);

        return abi.encode(abi.encodePacked(swapAction, uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)), params);
    }
}
