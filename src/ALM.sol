// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettlerSafe} from "@src/libraries/CurrencySettlerSafe.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";

// ** contracts
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

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
        IPoolManager manager,
        string memory name,
        string memory symbol
    ) BaseStrategyHook(manager) ERC20(name, symbol) {}

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
        _updateBoundaries();
        return ALM.afterInitialize.selector;
    }

    function deposit(address to, uint256 amountIn) external notPaused notShutdown returns (uint256, uint256) {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (amountIn == 0) revert ZeroLiquidity();
        refreshReserves();
        uint256 TVL1 = TVL();

        if (isInvertAssets) {
            IERC20(base).safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralShort(baseBalance(true));
        } else {
            IERC20(quote).safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralLong(quoteBalance(true));
        }
        uint256 TVL2 = TVL();
        if (TVL2 > tvlCap) revert TVLCapExceeded();

        uint256 _shares = ALMMathLib.getSharesToMint(TVL1, TVL2, totalSupply());
        _mint(to, _shares);
        emit Deposit(to, amountIn, _shares, TVL2, totalSupply());

        return (amountIn, _shares);
    }

    function withdraw(address to, uint256 sharesOut, uint256 minAmountOutB, uint256 minAmountOutQ) external notPaused {
        if (liquidityOperator != address(0) && liquidityOperator != msg.sender) revert NotALiquidityOperator();
        if (balanceOf(msg.sender) < sharesOut) revert NotEnoughSharesToWithdraw();
        if (sharesOut == 0) revert NotZeroShares();
        refreshReserves();

        (uint256 uCL, uint256 uCS, uint256 uDL, uint256 uDS) = ALMMathLib.getUserAmounts(
            totalSupply(),
            sharesOut,
            lendingAdapter.getCollateralLong(),
            lendingAdapter.getCollateralShort(),
            lendingAdapter.getBorrowedLong(),
            lendingAdapter.getBorrowedShort()
        );

        _burn(msg.sender, sharesOut);
        if (uDS != 0 && uDL != 0)
            lendingAdapter.flashLoanTwoTokens(base, uDL.unwrap(bDec), quote, uDS.unwrap(qDec), abi.encode(uCL, uCS));
        else if (uDS == 0 && uDL == 0) {
            if (uCL != 0) lendingAdapter.removeCollateralLong(uCL);
            if (uCS != 0) lendingAdapter.removeCollateralShort(uCS);
            if (isInvertAssets) swapAdapter.swapExactInput(quote, base, quoteBalance(false));
            else swapAdapter.swapExactInput(base, quote, baseBalance(false));
        } else if (uDL > 0) lendingAdapter.flashLoanSingle(base, uDL.unwrap(bDec), abi.encode(uCL, uCS));
        else revert NotAValidPositionState();

        uint256 baseOut;
        uint256 quoteOut;
        if (isInvertAssets) {
            baseOut = baseBalance(false);
            if (baseOut < minAmountOutB) revert NotMinOutWithdrawBase();
            IERC20(base).safeTransfer(to, baseOut);
        } else {
            quoteOut = quoteBalance(false);
            if (quoteOut < minAmountOutQ) revert NotMinOutWithdrawQuote();
            IERC20(quote).safeTransfer(to, quoteOut);
        }

        liquidity = rebalanceAdapter.calcLiquidity();
        emit Withdraw(to, sharesOut, baseOut, quoteOut, TVL(), totalSupply(), liquidity);
    }

    function onFlashLoanTwoTokens(
        address base,
        uint256 amount0,
        address quote,
        uint256 amount1,
        bytes calldata data
    ) external notPaused onlyLendingAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        lendingAdapter.repayLong(amount0.wrap(bDec));
        lendingAdapter.repayShort(amount1.wrap(qDec));

        lendingAdapter.removeCollateralLong(uCL);
        lendingAdapter.removeCollateralShort(uCS);

        if (isInvertAssets) _ensureEnoughBalance(amount1, quote);
        else _ensureEnoughBalance(amount0, base);
    }

    function onFlashLoanSingle(
        address token,
        uint256 amount,
        bytes calldata data
    ) external notPaused onlyLendingAdapter {
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        if (token == base) lendingAdapter.repayLong(amount.wrap(bDec));
        else lendingAdapter.repayShort(amount.wrap(qDec));

        lendingAdapter.removeCollateralLong(uCL);
        lendingAdapter.removeCollateralShort(uCS);

        if (token == base) {
            if (isInvertAssets) swapAdapter.swapExactInput(quote, base, quoteBalance(false));
            else _ensureEnoughBalance(amount, base);
        } else {
            if (isInvertAssets) _ensureEnoughBalance(amount, quote);
            else swapAdapter.swapExactInput(base, quote, baseBalance(false));
        }
    }

    function _ensureEnoughBalance(uint256 balance, address token) internal {
        uint256 _balance = token == base ? baseBalance(false) : quoteBalance(false);
        if (balance >= _balance) {
            swapAdapter.swapExactOutput(otherToken(token), token, balance - _balance);
        } else {
            swapAdapter.swapExactInput(token, otherToken(token), _balance - balance);
        }
    }

    // --- Swapping logic --- //

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
        refreshReserves();

        if (params.zeroForOne) {
            // If user is selling Token 0 and buying Token 1 (TOKEN0 => TOKEN1)
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 token0In,
                uint256 token1Out,
                uint160 sqrtPriceNext,
                uint256 fee
            ) = getZeroForOneDeltas(params.amountSpecified);

            checkSwapDeviations(sqrtPriceNext);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), token0In, false);

            if (isInvertedPool) {
                accumulatedFeeB += fee.mul(protocolFee); //cut protocol fee from the calculated swap fee
                positionManager.positionAdjustmentPriceUp(
                    (token0In - fee.mul(protocolFee)).wrap(bDec),
                    token1Out.wrap(qDec)
                );
            } else {
                accumulatedFeeQ += fee.mul(protocolFee);
                positionManager.positionAdjustmentPriceDown(
                    token1Out.wrap(bDec),
                    (token0In - fee.mul(protocolFee)).wrap(qDec)
                );
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
                uint256 token0Out,
                uint256 token1In,
                uint160 sqrtPriceNext,
                uint256 fee
            ) = getOneForZeroDeltas(params.amountSpecified);
            key.currency1.take(poolManager, address(this), token1In, false);

            checkSwapDeviations(sqrtPriceNext);
            if (isInvertedPool) {
                accumulatedFeeQ += fee.mul(protocolFee);
                positionManager.positionAdjustmentPriceDown(
                    token0Out.wrap(bDec),
                    (token1In - fee.mul(protocolFee)).wrap(qDec)
                );
            } else {
                accumulatedFeeB += fee.mul(protocolFee);
                positionManager.positionAdjustmentPriceUp(
                    (token1In - fee.mul(protocolFee)).wrap(bDec),
                    token0Out.wrap(qDec)
                );
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
        if (zeroForOne) {
            (, token0, token1, , ) = getZeroForOneDeltas(amountSpecified);
        } else {
            (, token0, token1, , ) = getOneForZeroDeltas(amountSpecified);
        }
    }

    function transferFees() external onlyRebalanceAdapter {
        IERC20(base).safeTransfer(treasury, accumulatedFeeB);
        IERC20(quote).safeTransfer(treasury, accumulatedFeeQ);
        accumulatedFeeB = 0;
        accumulatedFeeQ = 0;
    }

    function refreshReserves() public notPaused {
        lendingAdapter.syncLong();
        lendingAdapter.syncShort();
    }

    function checkSwapDeviations(uint160 sqrtPriceNext) internal view {
        uint256 ratio = uint256(sqrtPriceNext).div(rebalanceAdapter.sqrtPriceAtLastRebalance());
        uint256 priceThreshold = ratio > 1e18 ? ratio - 1e18 : 1e18 - ratio;
        if (priceThreshold >= swapPriceThreshold) revert SwapPriceChangeTooHigh();
    }

    // --- Helpers --- //

    function baseBalance(bool wrap) public view returns (uint256) {
        return
            wrap
                ? (IERC20(base).balanceOf(address(this)) - accumulatedFeeB).wrap(bDec)
                : IERC20(base).balanceOf(address(this)) - accumulatedFeeB;
    }

    function quoteBalance(bool wrap) public view returns (uint256) {
        return
            wrap
                ? (IERC20(quote).balanceOf(address(this)) - accumulatedFeeQ).wrap(qDec)
                : IERC20(quote).balanceOf(address(this)) - accumulatedFeeQ;
    }

    // --- Math functions --- //

    function TVL() public view returns (uint256) {
        return
            ALMMathLib.getTVL(
                quoteBalance(true),
                baseBalance(true),
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getBorrowedShort(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                oracle.price(),
                isInvertAssets
            );
    }

    function sharePrice() external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return TVL().div(totalSupply());
    }
}
