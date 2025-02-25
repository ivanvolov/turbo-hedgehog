// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** v4 imports
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettlerSafe} from "@src/libraries/CurrencySettlerSafe.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {PRBMathUD60x18} from "@src/libraries/math/PRBMathUD60x18.sol";
import "forge-std/console.sol";

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
        address,
        PoolKey calldata key,
        uint160 sqrtPrice,
        int24
    ) external override onlyPoolManager onlyAuthorizedPool(key) notPaused notShutdown returns (bytes4) {
        console.log("afterInitialize: sqrtPrice = %s", sqrtPrice);
        sqrtPriceCurrent = sqrtPrice;
        _updateBoundaries();
        return ALM.afterInitialize.selector;
    }

    function deposit(address to, uint256 amountIn) external notPaused notShutdown returns (uint256, uint256) {
        console.log("deposit: amountIn = %s", amountIn);
        if (amountIn == 0) revert ZeroLiquidity();
        refreshReserves();
        uint256 TVL1 = TVL();
        console.log("deposit: TVL1 = %s", TVL1);

        if (isInvertAssets) {
            console.log("deposit: isInvertAssets = true");
            IERC20(base).safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralShort(baseBalance(true));
        } else {
            console.log("deposit: isInvertAssets = false");
            IERC20(quote).safeTransferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralLong(quoteBalance(true));
        }

        uint256 _shares = ALMMathLib.getSharesToMint(TVL1, TVL(), totalSupply());
        console.log("deposit: _shares = %s", _shares);
        _mint(to, _shares);
        emit Deposit(msg.sender, amountIn, _shares);

        return (amountIn, _shares);
    }

    function withdraw(address to, uint256 sharesOut, uint256 minAmountOut) external notPaused {
        console.log("withdraw: sharesOut = %s", sharesOut);
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
        console.log("withdraw: uCL = %s", uCL);
        console.log("withdraw: uCS = %s", uCS);
        console.log("withdraw: uDL = %s", uDL);
        console.log("withdraw: uDS = %s", uDS);

        _burn(msg.sender, sharesOut);
        if (uDS != 0 && uDL != 0) {
            lendingAdapter.flashLoanTwoTokens(base, uDL.unwrap(bDec), quote, uDS.unwrap(qDec), abi.encode(uCL, uCS));
        } else if (uDS == 0 && uDL == 0) {
            lendingAdapter.removeCollateralLong(uCL);
            lendingAdapter.removeCollateralShort(uCS);
            if (isInvertAssets) swapAdapter.swapExactOutput(quote, base, quoteBalance(false));
            else swapAdapter.swapExactInput(base, quote, baseBalance(false));
        } else if (uDL > 0) lendingAdapter.flashLoanSingle(base, uDL.unwrap(bDec), abi.encode(uCL, uCS));
        else lendingAdapter.flashLoanSingle(quote, uDS.unwrap(qDec), abi.encode(uCL, uCS));

        if (isInvertAssets) {
            if (baseBalance(false) < minAmountOut) revert NotMinOutWithdraw();
            IERC20(base).safeTransfer(to, baseBalance(false));
        } else {
            if (quoteBalance(false) < minAmountOut) revert NotMinOutWithdraw();
            IERC20(quote).safeTransfer(to, quoteBalance(false));
        }

        liquidity = rebalanceAdapter.calcLiquidity();
        console.log("withdraw: liquidity = %s", liquidity);
    }

    function onFlashLoanTwoTokens(
        address base,
        uint256 amount0,
        address quote,
        uint256 amount1,
        bytes calldata data
    ) external notPaused onlyLendingAdapter {
        console.log("onFlashLoanTwoTokens: amount0 = %s, amount1 = %s", amount0, amount1);
        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        lendingAdapter.repayLong(amount0.wrap(bDec));
        lendingAdapter.repayShort(amount1.wrap(qDec));

        lendingAdapter.removeCollateralLong(uCL);
        lendingAdapter.removeCollateralShort(uCS);

        if (isInvertAssets) _ensureEnoughBalance(amount1, quote);
        else _ensureEnoughBalance(amount0, base);
    }

    function onFlashLoanSingle(address token, uint256 amount, bytes calldata data) public notPaused onlyLendingAdapter {
        console.log("onFlashLoanSingle: token = %s, amount = %s", token, amount);
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
        int256 delBalance = int256(balance) - int256(token == base ? baseBalance(false) : quoteBalance(false));
        if (delBalance > 0) {
            swapAdapter.swapExactOutput(otherToken(token), token, uint256(delBalance));
        } else if (delBalance < 0) {
            swapAdapter.swapExactInput(token, otherToken(token), ALMMathLib.abs(delBalance));
        }
    }

    function otherToken(address token) internal view returns (address) {
        return token == base ? quote : base;
    }

    // --- Swapping logic --- //

    function beforeSwap(
        address,
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
        return (this.beforeSwap.selector, _beforeSwap(params, key), 0);
    }

    // @Notice: this function is mainly for removing stack too deep error
    function _beforeSwap(
        IPoolManager.SwapParams calldata params,
        PoolKey calldata key
    ) internal returns (BeforeSwapDelta) {
        refreshReserves();

        if (params.zeroForOne) {
            console.log("_beforeSwap: zeroForOne = true");
            // If user is selling Token 0 and buying Token 1 (TOKEN0 => TOKEN1)
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 token0In,
                uint256 token1Out,
                uint160 sqrtPriceNext
            ) = getZeroForOneDeltas(params.amountSpecified);
            console.log(
                "_beforeSwap: token0In = %s, token1Out = %s, sqrtPriceNext = %s",
                token0In,
                token1Out,
                sqrtPriceNext
            );

            checkSwapDeviations(sqrtPriceNext);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), token0In, false);
            if (isInvertedPool) positionManager.positionAdjustmentPriceUp(token0In.wrap(bDec), token1Out.wrap(qDec));
            else positionManager.positionAdjustmentPriceDown(token1Out.wrap(bDec), token0In.wrap(qDec));

            // We also need to create a debit so user could take it back from the PM.
            key.currency1.settle(poolManager, address(this), token1Out, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        } else {
            console.log("_beforeSwap: zeroForOne = false");
            // If user is selling Token 1 and buying Token 0 (TOKEN1 => TOKEN0)
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 token0Out,
                uint256 token1In,
                uint160 sqrtPriceNext
            ) = getOneForZeroDeltas(params.amountSpecified);
            console.log(
                "_beforeSwap: token0Out = %s, token1In = %s, sqrtPriceNext = %s",
                token0Out,
                token1In,
                sqrtPriceNext
            );
            key.currency1.take(poolManager, address(this), token1In, false);

            checkSwapDeviations(sqrtPriceNext);
            if (isInvertedPool) positionManager.positionAdjustmentPriceDown(token0Out.wrap(bDec), token1In.wrap(qDec));
            else positionManager.positionAdjustmentPriceUp(token1In.wrap(bDec), token0Out.wrap(qDec));

            key.currency0.settle(poolManager, address(this), token0Out, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        }
    }

    function quoteSwap(bool zeroForOne, int256 amountSpecified) public view returns (uint256 token0, uint256 token1) {
        console.log("quoteSwap: zeroForOne = %s", zeroForOne);
        console.log("quoteSwap: amountSpecified = %s", amountSpecified);
        if (zeroForOne) {
            (, token0, token1, ) = getZeroForOneDeltas(amountSpecified);
        } else {
            (, token0, token1, ) = getOneForZeroDeltas(amountSpecified);
        }
    }

    function refreshReserves() public notPaused {
        console.log("refreshReserves: syncing reserves");
        lendingAdapter.syncLong();
        lendingAdapter.syncShort();
    }

    function checkSwapDeviations(uint160 sqrtPriceNext) internal view {
        console.log("checkSwapDeviations: sqrtPriceNext = %s", sqrtPriceNext);
        uint256 ratio = uint256(sqrtPriceNext).div(rebalanceAdapter.sqrtPriceAtLastRebalance());
        uint256 priceThreshold = ratio > 1e18 ? ratio - 1e18 : 1e18 - ratio;
        console.log("checkSwapDeviations: priceThreshold = %s", priceThreshold);
        if (priceThreshold >= swapPriceThreshold) revert SwapPriceChangeTooHigh();
    }

    // --- Helpers --- //

    function baseBalance(bool wrap) public view returns (uint256) {
        return wrap ? IERC20(base).balanceOf(address(this)).wrap(bDec) : IERC20(base).balanceOf(address(this));
    }

    function quoteBalance(bool wrap) public view returns (uint256) {
        return wrap ? IERC20(quote).balanceOf(address(this)).wrap(qDec) : IERC20(quote).balanceOf(address(this));
    }

    // --- Math functions --- //

    function TVL() public view returns (uint256) {
        uint256 tvl = ALMMathLib.getTVL(
            quoteBalance(true),
            baseBalance(true),
            lendingAdapter.getCollateralLong(),
            lendingAdapter.getBorrowedShort(),
            lendingAdapter.getCollateralShort(),
            lendingAdapter.getBorrowedLong(),
            oracle.price(),
            isInvertAssets
        );
        console.log("TVL: tvl = %s", tvl);
        return tvl;
    }

    function sharePrice() external view returns (uint256) {
        uint256 price = totalSupply() == 0 ? 0 : TVL().div(totalSupply());
        console.log("sharePrice: price = %s", price);
        return price;
    }
}
