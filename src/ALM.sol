// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** v4 imports
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {BaseStrategyHook} from "@src/core/base/BaseStrategyHook.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

// ** interfaces
import {AggregatorV3Interface} from "@forks/morpho-oracles/AggregatorV3Interface.sol";
import {Position as MorphoPosition, Id, Market} from "@forks/morpho/IMorpho.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

/// @title ALM
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALM is BaseStrategyHook, ERC20 {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;
    using TokenWrapperLib for uint256;

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
        console.log("> afterInitialize");
        sqrtPriceCurrent = sqrtPrice;
        _updateBoundaries();
        return ALM.afterInitialize.selector;
    }

    function deposit(address to, uint256 amountIn) external notPaused notShutdown returns (uint256, uint256) {
        console.log("Deposit");

        if (amountIn == 0) revert ZeroLiquidity();
        refreshReserves();
        uint256 TVL1 = TVL();

        if (isInvertAssets) {
            IERC20(token0).transferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralShort(token0Balance(true));
        } else {
            IERC20(token1).transferFrom(msg.sender, address(this), amountIn);
            lendingAdapter.addCollateralLong(token1Balance(true));
        }

        uint256 _shares = ALMMathLib.getSharesToMint(TVL1, TVL(), totalSupply());
        _mint(to, _shares);
        emit Deposit(msg.sender, amountIn, _shares);

        console.log("DepositDone");

        return (amountIn, _shares);
    }

    function withdraw(address to, uint256 sharesOut, uint256 minAmountOut) external notPaused {
        console.log("Withdraw");

        console.log("sharesOut %s", sharesOut);
        console.log("totalSupply %s", totalSupply());

        if (balanceOf(msg.sender) < sharesOut) revert NotEnoughSharesToWithdraw();
        if (sharesOut == 0) revert NotZeroShares();
        refreshReserves();

        console.log("preCL %s", lendingAdapter.getCollateralLong());
        console.log("preCS %s", lendingAdapter.getCollateralShort());
        console.log("preDL %s", lendingAdapter.getBorrowedLong());
        console.log("preDS %s", lendingAdapter.getBorrowedShort());

        (uint256 uCL, uint256 uCS, uint256 uDL, uint256 uDS) = ALMMathLib.getUserAmounts(
            totalSupply(),
            sharesOut,
            lendingAdapter.getCollateralLong(),
            lendingAdapter.getCollateralShort(),
            lendingAdapter.getBorrowedLong(),
            lendingAdapter.getBorrowedShort()
        );

        console.log("uCL %s", uCL);
        console.log("uCS %s", uCS);
        console.log("uDL %s", uDL);
        console.log("uDS %s", uDS);

        uint256 preTVL = alm.TVL();

        console.log("TVL %s", preTVL);

        _burn(msg.sender, sharesOut);
        if (uDS != 0 && uDL != 0) {
            address[] memory assets = new address[](2);
            uint256[] memory amounts = new uint256[](2);
            uint256[] memory modes = new uint256[](2);
            (assets[0], amounts[0], modes[0]) = (token0, uDL.unwrap(t0Dec), 0);
            (assets[1], amounts[1], modes[1]) = (token1, uDS.unwrap(t1Dec), 0);
            LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), abi.encode(uCL, uCS), 0);
        } else if (uDS == 0 && uDL == 0) {
            lendingAdapter.removeCollateralLong(uCL);
            lendingAdapter.removeCollateralShort(uCS);
            if (isInvertAssets) swapAdapter.swapExactOutput(token1, token0, token1Balance(false));
            else swapAdapter.swapExactInput(token0, token1, token0Balance(false));
        } else if (uDL > 0) {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            uint256[] memory modes = new uint256[](1);
            (assets[0], amounts[0], modes[0]) = (token0, uDL.unwrap(t0Dec), 0);
            LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), abi.encode(uCL, uCS), 0);
        } else {
            address[] memory assets = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            uint256[] memory modes = new uint256[](1);
            (assets[0], amounts[0], modes[0]) = (token1, uDS.unwrap(t1Dec), 0);
            LENDING_POOL.flashLoan(address(this), assets, amounts, modes, address(this), abi.encode(uCL, uCS), 0);
        }

        if (isInvertAssets) {
            if (token0Balance(false) < minAmountOut) revert NotMinOutWithdraw();
            IERC20(token0).transfer(to, token0Balance(false));
        } else {
            if (token1Balance(false) < minAmountOut) revert NotMinOutWithdraw();
            IERC20(token1).transfer(to, token1Balance(false));
        }

        liquidity = rebalanceAdapter.calcLiquidity();
        console.log("liquidity %s", liquidity);

        console.log("WithdrawDone");
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address,
        bytes calldata data
    ) external notPaused returns (bool) {
        // console.log("executeOperation");
        require(msg.sender == lendingPool, "M0");

        (uint256 uCL, uint256 uCS) = abi.decode(data, (uint256, uint256));

        if (assets[0] == token0) lendingAdapter.repayLong(amounts[0].wrap(t0Dec));
        if (assets[0] == token1 || assets.length == 2) lendingAdapter.repayShort(amounts[1].wrap(t1Dec));

        lendingAdapter.removeCollateralLong(uCL);
        lendingAdapter.removeCollateralShort(uCS);

        if (assets.length == 2) {
            if (isInvertAssets) {
                _ensureEnoughBalance(amounts[1] + premiums[1], token0);
            } else {
                _ensureEnoughBalance(amounts[0] + premiums[0], token0);
            }
        } else if (assets[0] == token0) {
            if (isInvertAssets) {
                swapAdapter.swapExactInput(token1, token0, token1Balance(false));
            } else {
                _ensureEnoughBalance(amounts[0] + premiums[0], token0);
            }
        } else if (assets[0] == token1) {
            if (isInvertAssets) {
                _ensureEnoughBalance(amounts[1] + premiums[1], token1);
            } else {
                swapAdapter.swapExactInput(token0, token1, token0Balance(false));
            }
        }

        return true;
    }

    function _ensureEnoughBalance(uint256 balance, address token) internal {
        int256 delBalance = int256(balance) - int256(token == token0 ? token0Balance(false) : token1Balance(false));
        if (delBalance > 0) {
            swapAdapter.swapExactOutput(otherToken(token), token, uint256(delBalance));
        } else if (delBalance < 0) {
            swapAdapter.swapExactInput(token, otherToken(token), ALMMathLib.abs(delBalance));
        }
    }

    function otherToken(address token) internal view returns (address) {
        return token == token0 ? token1 : token0;
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
            // If user is selling Token 0 and buying Token 1 (USDC => WETH)
            console.log("> USDC => WETH");
            (
                BeforeSwapDelta beforeSwapDelta,
                uint256 wethOut,
                uint256 usdcIn,
                uint160 sqrtPriceNext
            ) = getZeroForOneDeltas(params.amountSpecified);
            // console.log("> wethOut", wethOut);
            // console.log("> usdcIn", usdcIn);

            checkSwapDeviations(sqrtPriceNext);

            // They will be sending Token 0 to the PM, creating a debit of Token 0 in the PM
            // We will take actual ERC20 Token 0 from the PM and keep it in the hook and create an equivalent credit for that Token 0 since it is ours!
            key.currency0.take(poolManager, address(this), usdcIn, false);

            positionManager.positionAdjustmentPriceUp(usdcIn.wrap(t0Dec), wethOut.wrap(t1Dec));

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
            // console.log("> wethIn", wethIn);
            // console.log("> usdcOut", usdcOut);
            key.currency1.take(poolManager, address(this), wethIn, false);

            checkSwapDeviations(sqrtPriceNext);

            positionManager.positionAdjustmentPriceDown(usdcOut.wrap(t0Dec), wethIn.wrap(t1Dec));

            key.currency0.settle(poolManager, address(this), usdcOut, false);
            sqrtPriceCurrent = sqrtPriceNext;
            return beforeSwapDelta;
        }
    }

    function quoteSwap(bool zeroForOne, int256 amountSpecified) public view returns (uint256, uint256) {
        if (zeroForOne) {
            (, uint256 wethOut, uint256 usdcIn, ) = getZeroForOneDeltas(amountSpecified);
            return (usdcIn, wethOut);
        } else {
            (, uint256 wethIn, uint256 usdcOut, ) = getOneForZeroDeltas(amountSpecified);
            return (usdcOut, wethIn);
        }
    }

    function refreshReserves() public notPaused {
        lendingAdapter.syncLong();
        lendingAdapter.syncShort();
    }

    function checkSwapDeviations(uint160 sqrtPriceNext) internal view {
        uint256 ratio = (uint256(sqrtPriceNext) * 1e18) / uint256(sqrtPriceCurrent);
        uint256 priceThreshold = ratio > 1e18 ? ratio - 1e18 : 1e18 - ratio;
        console.log("checkSwapDeviations:", priceThreshold);
        if (priceThreshold >= swapPriceThreshold) revert SwapPriceChangeTooHigh();
    }

    // --- Helpers --- //

    function token0Balance(bool wrap) public view returns (uint256) {
        return wrap ? IERC20(token0).balanceOf(address(this)).wrap(t0Dec) : IERC20(token0).balanceOf(address(this));
    }

    function token1Balance(bool wrap) public view returns (uint256) {
        return wrap ? IERC20(token1).balanceOf(address(this)).wrap(t1Dec) : IERC20(token1).balanceOf(address(this));
    }

    // --- Math functions --- //

    //TODO: I would remove balances, cause money can't be withdraws from ALM so no need to account for them
    function TVL() public view returns (uint256) {
        return
            isInvertAssets
                ? ALMMathLib.getTVLStable(
                    token1Balance(true),
                    token0Balance(true),
                    lendingAdapter.getCollateralLong(),
                    lendingAdapter.getBorrowedShort(),
                    lendingAdapter.getCollateralShort(),
                    lendingAdapter.getBorrowedLong(),
                    oracle.price()
                )
                : ALMMathLib.getTVL(
                    token1Balance(true),
                    token0Balance(true),
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
}
