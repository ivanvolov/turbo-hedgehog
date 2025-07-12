// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

// ** External imports
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// ** libraries
import {ALMMathLib} from "./libraries/ALMMathLib.sol";
import {CurrencySettler} from "./libraries/CurrencySettler.sol";

// ** contracts
import {BaseStrategyHook} from "./core/base/BaseStrategyHook.sol";

/// @title Automated Liquidity Manager
/// @author Ivan Volovyk <https://github.com/ivanvolov>
/// @custom:contact ivan@lumis.fi
/// @notice The main hook contract handling liquidity management and swap flow.
contract ALM is BaseStrategyHook, ERC20, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;
    using LPFeeLibrary for uint24;

    constructor(
        PoolKey memory _key,
        IERC20 _base,
        IERC20 _quote,
        bool _isInvertedPool,
        bool _isInvertedAssets,
        IPoolManager _poolManager,
        string memory name,
        string memory symbol
    ) BaseStrategyHook(_base, _quote, _isInvertedPool, _isInvertedAssets, _poolManager) ERC20(name, symbol) {
        authorizedPool = PoolId.unwrap(_key.toId());
        authorizedPoolKey = _key;
    }

    function _afterInitialize(
        address creator,
        PoolKey calldata key,
        uint160 sqrtPrice,
        int24
    ) internal override onlyActive onlyAuthorizedPool(key) returns (bytes4) {
        if (!key.fee.isDynamicFee()) revert MustUseDynamicFee();
        if (creator != owner) revert OwnableUnauthorizedAccount(creator);
        _updatePriceAndBoundaries(sqrtPrice);

        return IHooks.afterInitialize.selector;
    }

    function deposit(
        address to,
        uint256 amountIn,
        uint256 minShares
    ) external onlyActive nonReentrant returns (uint256 sharesMinted) {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (amountIn == 0) revert ZeroLiquidity();
        lendingAdapter.syncPositions();
        uint256 price = oracle.price();
        uint256 tvlBefore = TVL(price);

        if (isInvertedAssets) {
            BASE.safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralShort(baseBalance(true));
        } else {
            QUOTE.safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralLong(quoteBalance(true));
        }
        uint256 tvlAfter = TVL(price);
        if (tvlAfter > tvlCap) revert TVLCapExceeded();

        sharesMinted = ALMMathLib.getSharesToMint(tvlBefore, tvlAfter, totalSupply());
        if (sharesMinted < minShares) revert NotMinShares();
        _mint(to, sharesMinted);
        emit Deposit(to, amountIn, sharesMinted, tvlAfter, totalSupply());
    }

    function withdraw(
        address to,
        uint256 sharesOut,
        uint256 minAmountOutB,
        uint256 minAmountOutQ
    ) external notPaused nonReentrant {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (sharesOut == 0) revert NotZeroShares();
        lendingAdapter.syncPositions();

        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        (uint256 uCL, uint256 uCS, uint256 uDL, uint256 uDS) = ALMMathLib.getUserAmounts(
            totalSupply(),
            sharesOut,
            CL,
            CS,
            DL,
            DS
        );

        _burn(msg.sender, sharesOut);
        if (uDS != 0 && uDL != 0) flashLoanAdapter.flashLoanTwoTokens(uDL, uDS, abi.encode(uCL, uCS));
        else if (uDS == 0 && uDL == 0) {
            if (uCL != 0 && uCS != 0)
                lendingAdapter.updatePosition(SafeCast.toInt256(uCL), SafeCast.toInt256(uCS), 0, 0);
            else if (uCL != 0) lendingAdapter.removeCollateralLong(uCL);
            else if (uCS != 0) lendingAdapter.removeCollateralShort(uCS);

            if (isInvertedAssets) swapAdapter.swapExactInput(false, quoteBalance(false));
            else swapAdapter.swapExactInput(true, baseBalance(false));
        } else if (uDL > 0) flashLoanAdapter.flashLoanSingle(true, uDL, abi.encode(uCL, uCS));
        else revert NotAValidPositionState();

        uint256 baseOut;
        uint256 quoteOut;
        if (isInvertedAssets) {
            baseOut = baseBalance(false);
            if (baseOut < minAmountOutB) revert NotMinOutWithdrawBase();
            BASE.safeTransfer(to, baseOut);
        } else {
            quoteOut = quoteBalance(false);
            if (quoteOut < minAmountOutQ) revert NotMinOutWithdrawQuote();
            QUOTE.safeTransfer(to, quoteOut);
        }

        uint128 newLiquidity = _calcLiquidity();
        liquidity = newLiquidity;
        emit Withdraw(to, sharesOut, baseOut, quoteOut, totalSupply(), newLiquidity);
    }

    function onFlashLoanTwoTokens(
        uint256 amountBase,
        uint256 amountQuote,
        bytes calldata data
    ) external notPaused onlyFlashLoanAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));
        lendingAdapter.updatePosition(
            SafeCast.toInt256(uCL),
            SafeCast.toInt256(uCS),
            -SafeCast.toInt256(amountBase),
            -SafeCast.toInt256(amountQuote)
        );

        if (isInvertedAssets) _ensureEnoughBalance(amountQuote, QUOTE);
        else _ensureEnoughBalance(amountBase, BASE);
    }

    function onFlashLoanSingle(
        bool isBase,
        uint256 amount,
        bytes calldata data
    ) external notPaused onlyFlashLoanAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        (int256 deltaDL, int256 deltaDS) = isBase
            ? (-SafeCast.toInt256(amount), int256(0))
            : (int256(0), -SafeCast.toInt256(amount));
        lendingAdapter.updatePosition(SafeCast.toInt256(uCL), SafeCast.toInt256(uCS), deltaDL, deltaDS);

        if (isBase) {
            if (isInvertedAssets) swapAdapter.swapExactInput(false, quoteBalance(false));
            else _ensureEnoughBalance(amount, BASE);
        } else {
            if (isInvertedAssets) _ensureEnoughBalance(amount, QUOTE);
            else swapAdapter.swapExactInput(true, baseBalance(false));
        }
    }

    function _ensureEnoughBalance(uint256 balance, IERC20 token) internal {
        uint256 _balance = token == BASE ? baseBalance(false) : quoteBalance(false);
        if (balance >= _balance) swapAdapter.swapExactOutput(token == QUOTE, balance - _balance);
        else swapAdapter.swapExactInput(token == BASE, _balance - balance);
    }

    function refreshReservesAndTransferFees() external onlyRebalanceAdapter {
        lendingAdapter.syncPositions();

        uint256 _accumulatedFee = accumulatedFeeB;
        accumulatedFeeB = 0;
        BASE.safeTransfer(treasury, _accumulatedFee);

        _accumulatedFee = accumulatedFeeQ;
        accumulatedFeeQ = 0;
        QUOTE.safeTransfer(treasury, _accumulatedFee);
    }

    // ** Swapping logic

    function quoteSwap(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public view returns (uint256 token0, uint256 token1) {
        // (, uint256 tokenIn, uint256 tokenOut, , ) = getDeltas(zeroForOne, amountSpecified, sqrtPriceLimitX96);
        // (token0, token1) = zeroForOne ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
    }

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
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override nonReentrant returns (bytes4, int128) {
        Ticks memory _activeTicks = activeTicks;

        (, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: _activeTicks.lower,
                tickUpper: _activeTicks.upper,
                liquidityDelta: -SafeCast.toInt256(poolManager.getLiquidity(PoolId.wrap(authorizedPool))),
                salt: bytes32(0)
            }),
            ""
        );

        _settleDeltas(
            params.zeroForOne,
            uint256(int256(SafeCast.toInt128(feesAccrued.amount0() + feesAccrued.amount1())))
        ); //?? Check, but one of them is always zero. Also check wtf is returned buy swap function, and modify liq function.

        return (IHooks.afterSwap.selector, 0);
    }

    function _settleDeltas(bool zeroForOne, uint256 feeAmount) internal {
        //? We did Sause have here >=. Does he expect to have a zero swap?
        if (zeroForOne) {
            uint256 token0In = uint256(poolManager.currencyDelta(address(this), authorizedPoolKey.currency0));
            uint256 token1Out = uint256(-poolManager.currencyDelta(address(this), authorizedPoolKey.currency1)); //? maybe unsigned here?

            authorizedPoolKey.currency0.take(poolManager, address(this), token0In, false);
            updatePosition(feeAmount, token0In, token1Out, isInvertedPool);
            authorizedPoolKey.currency1.settle(poolManager, address(this), token1Out, false);
        } else {
            uint256 token0Out = uint256(-poolManager.currencyDelta(address(this), authorizedPoolKey.currency0));
            uint256 token1In = uint256(poolManager.currencyDelta(address(this), authorizedPoolKey.currency1));

            authorizedPoolKey.currency1.take(poolManager, address(this), token1In, false);
            updatePosition(feeAmount, token1In, token0Out, !isInvertedPool);
            authorizedPoolKey.currency0.settle(poolManager, address(this), token0Out, false);
        }
    }

    // /// @dev This function is mainly for removing stack too deep error.
    // function __beforeSwap(
    //     SwapParams calldata params,
    //     PoolKey calldata key,
    //     address swapper
    // ) internal returns (BeforeSwapDelta) {
    //     lendingAdapter.syncPositions();

    //     if (params.zeroForOne) {
    //         // If user is selling Token 0 and buying Token 1 (TOKEN0 => TOKEN1)
    //         (
    //             BeforeSwapDelta beforeSwapDelta,
    //             uint256 token0In,
    //             uint256 token1Out,
    //             uint160 sqrtPriceNext,
    //             uint256 feeAmount
    //         ) = getDeltas(params.zeroForOne, params.amountSpecified, params.sqrtPriceLimitX96);
    //         checkSwapDeviations(sqrtPriceNext);

    //         // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
    //         // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
    //         key.currency0.take(poolManager, address(this), token0In, false);

    //         updatePosition(feeAmount, token0In, token1Out, isInvertedPool);

    //         // We also need to create a debit so user could take it back from the PM.
    //         key.currency1.settle(poolManager, address(this), token1Out, false);
    //         sqrtPriceCurrent = sqrtPriceNext;

    //         emit HookFee(authorizedPool, swapper, SafeCast.toUint128(feeAmount), 0);
    //         emit HookSwap(
    //             authorizedPool,
    //             swapper,
    //             SafeCast.toInt128(token0In),
    //             SafeCast.toInt128(token1Out),
    //             SafeCast.toUint128(feeAmount),
    //             0
    //         );
    //         return beforeSwapDelta;
    //     } else {
    //         // If user is selling Token 1 and buying Token 0 (TOKEN1 => TOKEN0)
    //         (
    //             BeforeSwapDelta beforeSwapDelta,
    //             uint256 token1In,
    //             uint256 token0Out,
    //             uint160 sqrtPriceNext,
    //             uint256 feeAmount
    //         ) = getDeltas(params.zeroForOne, params.amountSpecified, params.sqrtPriceLimitX96);
    //         checkSwapDeviations(sqrtPriceNext);

    //         key.currency1.take(poolManager, address(this), token1In, false);

    //         updatePosition(feeAmount, token1In, token0Out, !isInvertedPool);

    //         key.currency0.settle(poolManager, address(this), token0Out, false);
    //         sqrtPriceCurrent = sqrtPriceNext;

    //         emit HookFee(authorizedPool, swapper, 0, SafeCast.toUint128(feeAmount));
    //         emit HookSwap(
    //             authorizedPool,
    //             swapper,
    //             SafeCast.toInt128(token0Out),
    //             SafeCast.toInt128(token1In),
    //             0,
    //             SafeCast.toUint128(feeAmount)
    //         );
    //         return beforeSwapDelta;
    //     }
    // }

    function updatePosition(uint256 feeAmount, uint256 tokenIn, uint256 tokenOut, bool up) internal {
        uint256 protocolFeeAmount = protocolFee == 0 ? 0 : feeAmount.mul(protocolFee);
        console.log("protocolFeeAmount %s", protocolFeeAmount);
        console.log("feeAmount %s", feeAmount);
        console.log("protocolFee %s", protocolFee);
        if (up) {
            accumulatedFeeB += protocolFeeAmount;
            positionManager.positionAdjustmentPriceUp((tokenIn - protocolFeeAmount), tokenOut);
        } else {
            accumulatedFeeQ += protocolFeeAmount;
            positionManager.positionAdjustmentPriceDown(tokenOut, (tokenIn - protocolFeeAmount));
        }
    }

    function checkSwapDeviations(uint160 sqrtPriceNext) internal view {
        uint256 sqrtPriceAtLastRebalance = rebalanceAdapter.sqrtPriceAtLastRebalance();
        uint256 priceThreshold = uint256(sqrtPriceNext).div(sqrtPriceAtLastRebalance);
        if (priceThreshold < ALMMathLib.WAD) priceThreshold = sqrtPriceAtLastRebalance.div(sqrtPriceNext);
        if (priceThreshold >= swapPriceThreshold) revert SwapPriceChangeTooHigh();
    }

    // ** Math functions

    function TVL(uint256 price) public view returns (uint256) {
        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        return ALMMathLib.getTVL(quoteBalance(true), baseBalance(true), CL, CS, DL, DS, price, isInvertedAssets);
    }

    // ** Helpers

    function baseBalance(bool wrap) internal view returns (uint256) {
        uint256 balance = BASE.balanceOf(address(this)) - accumulatedFeeB;
        return wrap ? balance : balance;
    }

    function quoteBalance(bool wrap) internal view returns (uint256) {
        uint256 balance = QUOTE.balanceOf(address(this)) - accumulatedFeeQ;
        return wrap ? balance : balance;
    }
}
