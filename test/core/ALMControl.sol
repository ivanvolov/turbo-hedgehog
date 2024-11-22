// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {ERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {FixedPoint128} from "v4-core/libraries/FixedPoint128.sol";
import {FullMath} from "v4-core/libraries/FullMath.sol";

import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {PRBMathUD60x18} from "../../src/libraries/math/PRBMathUD60x18.sol";
import {ABDKMath64x64} from "../../src/libraries/math/ABDKMath64x64.sol";

import {IALM} from "@src/interfaces/IALM.sol";

/// @title ALM Control hook for simulation
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract ALMControl is BaseHook, ERC20 {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using PRBMathUD60x18 for uint256;

    IALM hook;

    PoolKey key;

    int24 public tickLower;
    int24 public tickUpper;

    constructor(IPoolManager _manager, address _hook) BaseHook(_manager) ERC20("ALMControl", "hhALMControl") {
        hook = IALM(_hook);
        tickLower = nearestUsableTick(hook.tickLower(), 2);
        tickUpper = nearestUsableTick(hook.tickUpper(), 2);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    // This should be called after the target hook is rebalanced
    function rebalance() external {
        (uint128 totalLiquidity, , ) = getPositionInfo();

        // ** Withdraw all liquidity
        poolManager.unlock(
            abi.encodeCall(
                this.unlockModifyPosition,
                (key, -int128(totalLiquidity), tickUpper, tickLower, address(this))
            )
        );

        uint256 _TVL = TVL();
        // console.log("TVL before:", TVL());

        // ** All money to rebalancer
        key.currency0.transfer(msg.sender, key.currency0.balanceOf(address(this)));
        key.currency1.transfer(msg.sender, key.currency1.balanceOf(address(this)));

        tickLower = nearestUsableTick(hook.tickLower(), 2);
        tickUpper = nearestUsableTick(hook.tickUpper(), 2);

        uint128 newLiquidity = getLiquidityForValue(_TVL);
        // console.log("newLiquidity", newLiquidity);

        // console.log("Tick lower/upper");
        // console.logInt(tickLower);
        // console.logInt(tickUpper);

        // ** Deposit all liquidity
        poolManager.unlock(
            abi.encodeCall(this.unlockModifyPosition, (key, int128(newLiquidity), tickUpper, tickLower, msg.sender))
        );
        // console.log("TVL after:", TVL());
    }

    function deposit(uint256 amount) external {
        require(amount != 0);

        (uint160 sqrtPriceX96, ) = getTick();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtPriceAtTick(tickUpper),
            sqrtPriceX96,
            amount
        );

        uint256 TVL1 = TVL();
        uint256 _sharePrice = sharePrice();

        poolManager.unlock(
            abi.encodeCall(this.unlockModifyPosition, (key, int128(liquidity), tickUpper, tickLower, msg.sender))
        );

        if (_sharePrice == 0) {
            _mint(msg.sender, TVL());
        } else {
            uint256 shares = ((TVL() - TVL1) * 1e18) / _sharePrice;
            _mint(msg.sender, shares);
        }
    }

    function withdraw(uint256 shares) external {
        require(balanceOf(msg.sender) >= shares);

        //TODO: better do some poke here
        uint256 ratio = (shares * 1e18) / totalSupply();
        _burn(msg.sender, shares);
        (uint128 totalLiquidity, , ) = getPositionInfo();
        uint256 liquidityToBurn = (uint256(totalLiquidity) * (ratio)) / 1e18;

        poolManager.unlock(
            abi.encodeCall(
                this.unlockModifyPosition,
                (key, -int128(uint128(liquidityToBurn)), tickUpper, tickLower, msg.sender)
            )
        );
    }

    function sharePrice() public view returns (uint256) {
        if (totalSupply() == 0) return 0;
        return (TVL() * 1e18) / totalSupply();
    }

    function getTick() public view returns (uint160 sqrtPriceX96, int24 currentTick) {
        (sqrtPriceX96, currentTick, , ) = poolManager.getSlot0(key.toId());
    }

    function unlockModifyPosition(
        PoolKey calldata,
        int128 liquidity,
        int24 _tickLower,
        int24 _tickUpper,
        address sender
    ) external selfOnly returns (bytes memory) {
        // console.log("> unlockModifyPosition");

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: liquidity,
                salt: bytes32("")
            }),
            ""
        );

        if (delta.amount0() < 0) {
            key.currency0.settle(poolManager, sender, uint256(uint128(-delta.amount0())), false);
            // console.log("amount0", uint256(uint128(-delta.amount0())));
        }

        if (delta.amount0() > 0) {
            key.currency0.take(poolManager, sender, uint256(uint128(delta.amount0())), false);
        }

        if (delta.amount1() < 0) {
            key.currency1.settle(poolManager, sender, uint256(uint128(-delta.amount1())), false);
            // console.log("amount1", uint256(uint128(-delta.amount1())));
        }

        if (delta.amount1() > 0) {
            key.currency1.take(poolManager, sender, uint256(uint128(delta.amount1())), false);
        }
        return "";
    }

    function TVL() public view returns (uint256) {
        (uint256 amount0, uint256 amount1) = getUniswapPositionAmounts();
        return TVL(amount0 + key.currency0.balanceOf(address(this)), amount1 + key.currency1.balanceOf(address(this)));
    }

    function TVL(uint256 amount0, uint256 amount1) public view returns (uint256) {
        // console.log("getTVL");
        // console.log("amount0", amount0);
        // console.log("amount1", amount1);
        // console.log("current price", _calcCurrentPrice());
        return amount1 + (amount0 * 1e30) / _calcCurrentPrice();
    }

    function getUniswapPositionAmounts() public view returns (uint256, uint256) {
        (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) = getPositionInfo();

        (uint160 sqrtPriceX96, ) = getTick();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickUpper),
            TickMath.getSqrtPriceAtTick(tickLower),
            liquidity
        );

        uint256 owed0 = FullMath.mulDiv(feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);

        uint256 owed1 = FullMath.mulDiv(feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);
        //TODO: check if this fee calculation is working good
        return (amount0 + owed0, amount1 + owed1);
    }

    function getPositionInfo() public view returns (uint128, uint256, uint256) {
        return poolManager.getPositionInfo(key.toId(), address(this), tickUpper, tickLower, bytes32(""));
    }

    function _calcCurrentPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96, ) = getTick();
        return ALMMathLib.getPriceFromSqrtPriceX96(sqrtPriceX96);
    }

    function afterInitialize(
        address,
        PoolKey calldata _key,
        uint160,
        int24,
        bytes calldata
    ) external override returns (bytes4) {
        key = _key;
        return ALMControl.afterInitialize.selector;
    }

    // ** Helpers

    function getLiquidityForValue(uint256 value) public view returns (uint128) {
        (, int24 currentTick) = getTick();
        return
            _getLiquidityForValue(
                value,
                uint256(1e30).div(_getPriceFromTick(currentTick)),
                uint256(1e30).div(_getPriceFromTick(tickUpper)),
                uint256(1e30).div(_getPriceFromTick(tickLower)),
                1e12
            );
    }

    function _getPriceFromTick(int24 tick) internal pure returns (uint256) {
        uint160 sqrtRatioAtTick = TickMath.getSqrtPriceAtTick(tick);
        //const = 2^192
        return
            (uint256(sqrtRatioAtTick)).pow(uint256(2e18)).mul(1e36).div(
                6277101735386680763835789423207666416102355444464034512896
            );
    }

    function _getLiquidityForValue(
        uint256 v,
        uint256 p,
        uint256 pH,
        uint256 pL,
        uint256 digits
    ) internal pure returns (uint128) {
        // console.log("_getLiquidityForValue");
        // console.log(v);
        // console.log(p);
        // console.log(pH);
        // console.log(pL);
        // console.log(digits);

        v = v.mul(p);
        return uint128(v.div((p.sqrt()).mul(2e18) - pL.sqrt() - p.div(pH.sqrt())).mul(digits));
    }

    function nearestUsableTick(int24 tick_, uint24 tickSpacing) internal pure returns (int24 result) {
        result = int24(divRound(int128(tick_), int128(int24(tickSpacing)))) * int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }

    function divRound(int128 x, int128 y) internal pure returns (int128 result) {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;

        // Check if remainder is greater than 0.5
        if (quot % 2 ** 64 >= 0x8000000000000000) {
            result += 1;
        }
    }
}
