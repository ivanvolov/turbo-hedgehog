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

    function deposit(address to, uint256 amount) external notPaused notShutdown returns (uint256, uint256) {
        if (amount == 0) revert ZeroLiquidity();
        refreshReserves();
        uint256 TVL1 = TVL();

        (uint128 deltaLiquidity, uint256 amountIn) = _calcDepositLiquidity(amount);
        WETH.transferFrom(msg.sender, address(this), amountIn);
        liquidity = liquidity + deltaLiquidity;

        lendingAdapter.addCollateralLong(ALMBaseLib.wethBalance(address(this)));

        uint256 TVL2 = TVL();
        uint256 _shares = ALMMathLib.getSharesToMint(TVL1, TVL2, totalSupply());
        _mint(to, _shares);
        emit Deposit(msg.sender, amountIn, _shares);
        return (amountIn, _shares);
    }

    function withdraw(address to, uint256 sharesOut) external notPaused {}

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
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            console.log("> USDC => WETH");
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethOut,
                uint256 usdcIn,
                uint160 sqrtPriceNext
            ) = getZeroForOneDeltas(params.amountSpecified);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), usdcIn, false);

            positionManager.positionAdjustmentPriceUp(usdcIn, wethOut);

            // We also need to create a debit so user could take it back from the PM.
            key.currency1.settle(poolManager, address(this), wethOut, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        } else {
            // If user is selling Token 1 and buying Token 0 (WETH => USDC)
            console.log("> WETH => USDC");
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethIn,
                uint256 usdcOut,
                uint160 sqrtPriceNext
            ) = getOneForZeroDeltas(params.amountSpecified);
            key.currency1.take(poolManager, address(this), wethIn, false);

            positionManager.positionAdjustmentPriceDown(usdcOut, wethIn);

            key.currency0.settle(poolManager, address(this), usdcOut, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        }
    }

    function refreshReserves() public {
        lendingAdapter.syncLong();
        lendingAdapter.syncShort();
    }

    // ---- Math functions
    //TODO: I would remove balances, cause money can't be withdraws from ALM so no need to account for them
    function TVL() public view returns (uint256) {
        return
            ALMMathLib.getTVL(
                ALMBaseLib.wethBalance(address(this)),
                ALMBaseLib.usdcBalance(address(this)),
                lendingAdapter.getCollateralLong(),
                lendingAdapter.getBorrowedShort(),
                lendingAdapter.getCollateralShort(),
                lendingAdapter.getBorrowedLong(),
                oracle.price()
            );
    }

    function sharePrice() external view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (TVL() * 1e18) / totalSupply();
    }

    function _calcDepositLiquidity(uint256 amount) public view returns (uint128 _liquidity, uint256 _amount) {
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
