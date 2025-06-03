// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// ** External imports
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ** libraries
import {ALMMathLib} from "./libraries/ALMMathLib.sol";
import {TokenWrapperLib} from "./libraries/TokenWrapperLib.sol";
import {CurrencySettlerSafe} from "./libraries/CurrencySettlerSafe.sol";

// ** contracts
import {BaseStrategyHook} from "./core/base/BaseStrategyHook.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC20 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettlerSafe for Currency;
    using TokenWrapperLib for uint256;
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for IERC20;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        bool _isInvertedPool,
        bool _isInvertedAssets,
        IPoolManager manager,
        string memory name,
        string memory symbol
    ) BaseStrategyHook(_base, _quote, _bDec, _qDec, _isInvertedPool, _isInvertedAssets, manager) ERC20(name, symbol) {
        // Intentionally empty as all initialization is handled by the parent BaseStrategyHook contract
    }

    function afterInitialize(
        address creator,
        PoolKey calldata key,
        uint160 sqrtPrice,
        int24
    ) external override onlyPoolManager notPaused notShutdown returns (bytes4) {
        if (creator != owner) revert OwnableUnauthorizedAccount(creator);
        if (authorizedPool != bytes32("")) revert OnlyOnePoolPerHook();
        authorizedPool = PoolId.unwrap(key.toId());
        sqrtPriceCurrent = sqrtPrice;
        _updateBoundaries(sqrtPrice);
        return ALM.afterInitialize.selector;
    }

    function deposit(
        address to,
        uint256 amountIn,
        uint256 minShares
    ) external notPaused notShutdown returns (uint256 sharesMinted) {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (amountIn == 0) revert ZeroLiquidity();
        lendingAdapter.syncPositions();
        uint256 TVL1 = TVL();

        if (isInvertedAssets) {
            base.safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralShort(baseBalance(true));
        } else {
            quote.safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralLong(quoteBalance(true));
        }
        uint256 TVL2 = TVL();
        if (TVL2 > tvlCap) revert TVLCapExceeded();

        sharesMinted = ALMMathLib.getSharesToMint(TVL1, TVL2, totalSupply());
        if (sharesMinted < minShares) revert NotMinShares();
        _mint(to, sharesMinted);
        emit Deposit(to, amountIn, sharesMinted, TVL2, totalSupply());
    }

    function withdraw(address to, uint256 sharesOut, uint256 minAmountOutB, uint256 minAmountOutQ) external notPaused {
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
        if (uDS != 0 && uDL != 0)
            flashLoanAdapter.flashLoanTwoTokens(base, uDL.unwrap(bDec), quote, uDS.unwrap(qDec), abi.encode(uCL, uCS));
        else if (uDS == 0 && uDL == 0) {
            if (uCL != 0 && uCS != 0)
                lendingAdapter.updatePosition(SafeCast.toInt256(uCL), SafeCast.toInt256(uCS), 0, 0);
            else if (uCL != 0) lendingAdapter.removeCollateralLong(uCL);
            else if (uCS != 0) lendingAdapter.removeCollateralShort(uCS);

            if (isInvertedAssets) swapAdapter.swapExactInput(false, quoteBalance(false));
            else swapAdapter.swapExactInput(true, baseBalance(false));
        } else if (uDL > 0) flashLoanAdapter.flashLoanSingle(base, uDL.unwrap(bDec), abi.encode(uCL, uCS));
        else revert NotAValidPositionState();

        uint256 baseOut;
        uint256 quoteOut;
        if (isInvertedAssets) {
            baseOut = baseBalance(false);
            if (baseOut < minAmountOutB) revert NotMinOutWithdrawBase();
            base.safeTransfer(to, baseOut);
        } else {
            quoteOut = quoteBalance(false);
            if (quoteOut < minAmountOutQ) revert NotMinOutWithdrawQuote();
            quote.safeTransfer(to, quoteOut);
        }

        liquidity = rebalanceAdapter.calcLiquidity();
        emit Withdraw(to, sharesOut, baseOut, quoteOut, TVL(), totalSupply(), liquidity);
    }

    function onFlashLoanTwoTokens(
        IERC20 base,
        uint256 amount0,
        IERC20 quote,
        uint256 amount1,
        bytes calldata data
    ) external notPaused onlyFlashLoanAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));
        lendingAdapter.updatePosition(
            SafeCast.toInt256(uCL),
            SafeCast.toInt256(uCS),
            -SafeCast.toInt256(amount0.wrap(bDec)),
            -SafeCast.toInt256(amount1.wrap(qDec))
        );

        if (isInvertedAssets) _ensureEnoughBalance(amount1, quote);
        else _ensureEnoughBalance(amount0, base);
    }

    function onFlashLoanSingle(
        IERC20 token,
        uint256 amount,
        bytes calldata data
    ) external notPaused onlyFlashLoanAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        (int256 deltaDL, int256 deltaDS) = (token == base)
            ? (-SafeCast.toInt256(amount.wrap(bDec)), int256(0))
            : (int256(0), -SafeCast.toInt256(amount.wrap(qDec)));
        lendingAdapter.updatePosition(SafeCast.toInt256(uCL), SafeCast.toInt256(uCS), deltaDL, deltaDS);

        if (token == base) {
            if (isInvertedAssets) swapAdapter.swapExactInput(false, quoteBalance(false));
            else _ensureEnoughBalance(amount, base);
        } else {
            if (isInvertedAssets) _ensureEnoughBalance(amount, quote);
            else swapAdapter.swapExactInput(true, baseBalance(false));
        }
    }

    function _ensureEnoughBalance(uint256 balance, IERC20 token) internal {
        uint256 _balance = token == base ? baseBalance(false) : quoteBalance(false);
        if (balance >= _balance) {
            swapAdapter.swapExactOutput(token == quote, balance - _balance);
        } else {
            swapAdapter.swapExactInput(token == base, _balance - balance);
        }
    }

    // ** Swapping logic

    function beforeSwap(
        address swapper,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    )
        external
        override
        notPaused
        notShutdown
        onlyAuthorizedPool(key)
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (swapOperator != address(0) && swapOperator != swapper) revert NotASwapOperator();
        return (this.beforeSwap.selector, _beforeSwap(params, key, swapper), 0);
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _beforeSwap(
        IPoolManager.SwapParams calldata params,
        PoolKey calldata key,
        address swapper
    ) internal returns (BeforeSwapDelta) {
        lendingAdapter.syncPositions();

        if (params.zeroForOne) {
            // If user is selling Token 0 and buying Token 1 (TOKEN0 => TOKEN1)
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 token0In,
                uint256 token1Out,
                uint160 sqrtPriceNext,
                uint256 fee
            ) = getDeltas(params.amountSpecified, params.zeroForOne);
            checkSwapDeviations(sqrtPriceNext);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), token0In, false);

            uint256 protocolFeeAmount = fee.mul(protocolFee);
            if (params.amountSpecified > 0) {
                if (isInvertedPool) {
                    accumulatedFeeB += protocolFeeAmount; //cut protocol fee from the calculated swap fee
                    positionManager.positionAdjustmentPriceUp(
                        (token0In - protocolFeeAmount).wrap(bDec),
                        token1Out.wrap(qDec)
                    );
                } else {
                    accumulatedFeeQ += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceDown(
                        token1Out.wrap(bDec),
                        (token0In - protocolFeeAmount).wrap(qDec)
                    );
                }
            } else {
                if (isInvertedPool) {
                    accumulatedFeeB += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceUp(
                        (token0In - protocolFeeAmount).wrap(bDec),
                        (token1Out).wrap(qDec)
                    );
                } else {
                    accumulatedFeeQ += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceDown(
                        token1Out.wrap(bDec),
                        (token0In - protocolFeeAmount).wrap(qDec)
                    );
                }
            }

            // We also need to create a debit so user could take it back from the PM.
            key.currency1.settle(poolManager, address(this), token1Out, false);
            sqrtPriceCurrent = sqrtPriceNext;

            emit HookFee(authorizedPool, swapper, SafeCast.toUint128(fee), 0);
            emit HookSwap(
                authorizedPool,
                swapper,
                SafeCast.toInt128(token0In),
                SafeCast.toInt128(token1Out),
                SafeCast.toUint128(fee),
                0
            );
            return beforeSwapDelta;
        } else {
            // If user is selling Token 1 and buying Token 0 (TOKEN1 => TOKEN0)
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 token1In,
                uint256 token0Out,
                uint160 sqrtPriceNext,
                uint256 fee
            ) = getDeltas(params.amountSpecified, params.zeroForOne);
            checkSwapDeviations(sqrtPriceNext);

            key.currency1.take(poolManager, address(this), token1In, false);

            uint256 protocolFeeAmount = fee.mul(protocolFee);
            if (params.amountSpecified > 0) {
                if (isInvertedPool) {
                    accumulatedFeeQ += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceDown(
                        token0Out.wrap(bDec),
                        (token1In - protocolFeeAmount).wrap(qDec)
                    );
                } else {
                    accumulatedFeeB += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceUp(
                        (token1In - protocolFeeAmount).wrap(bDec),
                        token0Out.wrap(qDec)
                    );
                }
            } else {
                if (isInvertedPool) {
                    accumulatedFeeQ += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceDown(
                        token0Out.wrap(bDec),
                        (token1In - protocolFeeAmount).wrap(qDec)
                    );
                } else {
                    accumulatedFeeB += protocolFeeAmount;
                    positionManager.positionAdjustmentPriceUp(
                        (token1In - protocolFeeAmount).wrap(bDec),
                        token0Out.wrap(qDec)
                    );
                }
            }

            key.currency0.settle(poolManager, address(this), token0Out, false);
            sqrtPriceCurrent = sqrtPriceNext;

            emit HookFee(authorizedPool, swapper, 0, SafeCast.toUint128(fee));
            emit HookSwap(
                authorizedPool,
                swapper,
                SafeCast.toInt128(token0Out),
                SafeCast.toInt128(token1In),
                0,
                SafeCast.toUint128(fee)
            );
            return beforeSwapDelta;
        }
    }

    function quoteSwap(bool zeroForOne, int256 amountSpecified) public view returns (uint256 token0, uint256 token1) {
        (, uint256 tokenIn, uint256 tokenOut, , ) = getDeltas(amountSpecified, zeroForOne);
        (token0, token1) = zeroForOne ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
    }

    function transferFees() external onlyRebalanceAdapter {
        accumulatedFeeB = 0;
        base.safeTransfer(treasury, accumulatedFeeB);
        accumulatedFeeQ = 0;
        quote.safeTransfer(treasury, accumulatedFeeQ);
    }

    function refreshReserves() external notPaused {
        lendingAdapter.syncPositions();
    }

    function checkSwapDeviations(uint160 sqrtPriceNext) internal view {
        uint256 ratio = uint256(sqrtPriceNext).div(rebalanceAdapter.sqrtPriceAtLastRebalance());
        uint256 priceThreshold = ratio > 1e18 ? ratio - 1e18 : 1e18 - ratio;
        if (priceThreshold >= swapPriceThreshold) revert SwapPriceChangeTooHigh();
    }

    // ** Helpers

    function baseBalance(bool wrap) public view returns (uint256) {
        uint256 balance = base.balanceOf(address(this)) - accumulatedFeeB;
        return wrap ? balance.wrap(bDec) : balance;
    }

    function quoteBalance(bool wrap) public view returns (uint256) {
        uint256 balance = quote.balanceOf(address(this)) - accumulatedFeeQ;
        return wrap ? balance.wrap(qDec) : balance;
    }

    // ** Math functions

    function TVL() public view returns (uint256) {
        (uint256 CL, uint256 CS, uint256 DL, uint256 DS) = lendingAdapter.getPosition();
        return
            ALMMathLib.getTVL(quoteBalance(true), baseBalance(true), CL, CS, DL, DS, oracle.price(), isInvertedAssets);
    }

    function sharePrice() external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return TVL().div(totalSupply());
    }
}
