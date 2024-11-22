// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

import {ERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {BaseStrategyHook} from "@src/core/BaseStrategyHook.sol";
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC20 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    constructor(IPoolManager manager) BaseStrategyHook(manager) ERC20("ALM", "hhALM") {} // TODO: change name to production

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160 sqrtPrice,
        int24,
        bytes calldata
    ) external override onlyByPoolManager onlyAuthorizedPool(key) returns (bytes4) {
        console.log("> afterInitialize");
        sqrtPriceCurrent = sqrtPrice;
        _updateBoundaries();
        return ALM.afterInitialize.selector;
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

    function deposit(address to, uint256 amount) external notPaused notShutdown returns (uint256, uint256) {
        if (amount == 0) revert ZeroLiquidity();
        refreshReserves();
        (uint128 deltaL, uint256 amountIn, uint256 shares) = _calcDepositParams(amount);

        WETH.transferFrom(msg.sender, address(this), amountIn);
        lendingAdapter.addCollateral(WETH.balanceOf(address(this)));
        liquidity = liquidity + deltaL;

        _mint(to, shares);

        emit Deposit(msg.sender, amountIn, shares);
        return (amountIn, shares);
    }

    function withdraw(address to, uint256 sharesOut) external notPaused {
        if (balanceOf(msg.sender) < sharesOut) revert NotEnoughSharesToWithdraw();
        uint256 usdcToRepay = lendingAdapter.getBorrowed();
        uint256 usdcSupplied = lendingAdapter.getSupplied();
        if (usdcToRepay == 0) {
            if (usdcSupplied != 0) {
                console.log("> have usdc");
                // ** have usdc;
                lendingAdapter.withdraw(
                    ALMMathLib.getWithdrawAmount(sharesOut, totalSupply(), lendingAdapter.getSupplied())
                );
            }
            lendingAdapter.removeCollateral(
                ALMMathLib.getWithdrawAmount(sharesOut, totalSupply(), lendingAdapter.getCollateral())
            );
        } else if (usdcToRepay != 0 && usdcSupplied == 0) {
            console.log("> have usdc debt");
            // ** have usdc debt;
            IRebalanceAdapter(rebalanceAdapter).withdraw(
                ALMMathLib.getWithdrawAmount(sharesOut, totalSupply(), usdcToRepay),
                ALMMathLib.getWithdrawAmount(sharesOut, totalSupply(), lendingAdapter.getCollateral())
            );
        } else revert BalanceInconsistency();

        _burn(msg.sender, sharesOut);
        uint256 amount0 = USDC.balanceOf(address(this));
        uint256 amount1 = WETH.balanceOf(address(this));
        USDC.transfer(to, amount0);
        WETH.transfer(to, amount1);
        emit Withdraw(to, sharesOut, amount0, amount1);
    }

    // --- Swapping logic ---
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
        onlyByPoolManager
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
            console.log("> WETH price go up...");
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            // TLDR: Here we got USDC and save it on balance. And just give our ETH back to USER.
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethOut,
                uint256 usdcIn,
                uint160 sqrtPriceNext
            ) = getZeroForOneDeltas(params.amountSpecified);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), usdcIn, false);
            repayAndSupply(usdcIn); // Notice: repaying if needed to reduce lending interest.

            // We don't have token 1 on our account yet, so we need to withdraw WETH from the Morpho.
            // We also need to create a debit so user could take it back from the PM.
            lendingAdapter.removeCollateral(wethOut);
            key.currency1.settle(poolManager, address(this), wethOut, false);

            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        } else {
            console.log("> WETH price go down...");
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            // TLDR: Here we borrow USDC at Morpho and give it back.

            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethIn,
                uint256 usdcOut,
                uint160 sqrtPriceNext
            ) = getOneForZeroDeltas(params.amountSpecified);

            // Put extra WETH to Morpho
            key.currency1.take(poolManager, address(this), wethIn, false);
            lendingAdapter.addCollateral(wethIn);

            // Ensure we have enough USDC. Redeem from reserves and borrow if needed.
            redeemAndBorrow(usdcOut);
            key.currency0.settle(poolManager, address(this), usdcOut, false);

            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        }
    }

    // --- Internal and view functions ---

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

    function redeemAndBorrow(uint256 usdcOut) internal {
        uint256 withdrawAmount = ALMMathLib.min(lendingAdapter.getSupplied(), usdcOut);
        if (withdrawAmount > 0) lendingAdapter.withdraw(withdrawAmount);

        if (usdcOut > withdrawAmount) lendingAdapter.borrow(usdcOut - withdrawAmount);
    }

    function repayAndSupply(uint256 amountUSDC) internal {
        uint256 repayAmount = ALMMathLib.min(lendingAdapter.getBorrowed(), amountUSDC);
        if (repayAmount > 0) lendingAdapter.repay(repayAmount);
        if (amountUSDC > repayAmount) lendingAdapter.supply(amountUSDC - repayAmount);
    }

    function refreshReserves() public {
        lendingAdapter.syncBorrow();
        lendingAdapter.syncDeposit();
    }

    // ---- Math functions

    function TVL() public view returns (uint256) {
        uint256 price = _calcCurrentPrice();
        int256 tvl = int256(lendingAdapter.getCollateral()) +
            int256(lendingAdapter.getSupplied() / price) -
            int256(lendingAdapter.getBorrowed() / price);
        return uint256(tvl);
    }

    function sharePrice() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (TVL() * 1e18) / totalSupply();
    }

    function _calcCurrentPrice() public view returns (uint256) {
        return ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceCurrent);
    }

    function _calcDepositParams(
        uint256 amount
    ) public view returns (uint128 _liquidity, uint256 _amount, uint256 shares) {
        _liquidity = ALMMathLib.getLiquidityFromAmount1SqrtPriceX96(
            ALMMathLib.getSqrtPriceAtTick(tickUpper),
            sqrtPriceCurrent,
            amount
        );
        (, _amount) = ALMMathLib.getAmountsFromLiquiditySqrtPriceX96(
            sqrtPriceCurrent,
            ALMMathLib.getSqrtPriceAtTick(tickUpper),
            ALMMathLib.getSqrtPriceAtTick(tickLower),
            _liquidity
        );

        uint256 _sharePrice = sharePrice();
        shares = _sharePrice == 0 ? _amount : (_amount * 1e18) / _sharePrice;
    }

    // TODO: Notice * I'm not using it now in the code at all.
    function adjustForFeesDown(uint256 amount) public pure returns (uint256 amountAdjusted) {
        // console.log("> amount specified", amount);
        amountAdjusted = amount - (amount * getSwapFees()) / 1e18;
        // console.log("> amount adjusted ", amountAdjusted);
    }

    // TODO: Notice * I'm not using it now in the code at all.
    function adjustForFeesUp(uint256 amount) public pure returns (uint256 amountAdjusted) {
        // console.log("> amount specified", amount);
        amountAdjusted = amount + (amount * getSwapFees()) / 1e18;
        // console.log("> amount adjusted ", amountAdjusted);
    }

    function getSwapFees() public pure returns (uint256) {
        // TODO: do fees properly. Now it will be similar to the test pull (0.05)
        // return 50000000000000000;
        return 0;
        // (, int256 RV7, , , ) = AggregatorV3Interface(
        //     ALMBaseLib.CHAINLINK_7_DAYS_VOL
        // ).latestRoundData();
        // (, int256 RV30, , , ) = AggregatorV3Interface(
        //     ALMBaseLib.CHAINLINK_30_DAYS_VOL
        // ).latestRoundData();
        // return ALMMathLib.calculateSwapFee(RV7 * 1e18, RV30 * 1e18);
    }
}
