// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** external imports
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {TransientStateLibrary} from "v4-core/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

// ** libraries
import {div18} from "@src/libraries/ALMMathLib.sol";
import {CurrencySettler} from "@src/libraries/CurrencySettler.sol";

contract ArbV4V4 is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using CurrencySettler for Currency;

    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    IPoolManager public immutable poolManager;

    PoolKey public primaryPool;
    PoolKey public targetPool;
    PoolId public primaryPoolId;
    PoolId public targetPoolId;

    constructor(IPoolManager _poolManager) Ownable(msg.sender) {
        poolManager = _poolManager;
    }

    function setPools(PoolKey calldata _primaryPool, PoolKey calldata _targetPool) external onlyOwner {
        primaryPool = _primaryPool;
        targetPool = _targetPool;
        primaryPoolId = _primaryPool.toId();
        targetPoolId = _targetPool.toId();
    }

    function calcPriceRatio() public view returns (uint256, uint160, uint160) {
        (uint160 primarySqrtPrice, , , ) = poolManager.getSlot0(primaryPoolId);
        (uint160 targetSqrtPrice, , , ) = poolManager.getSlot0(targetPoolId);

        uint256 ratio = primarySqrtPrice > targetSqrtPrice
            ? div18(primarySqrtPrice, targetSqrtPrice)
            : div18(targetSqrtPrice, primarySqrtPrice);
        return (ratio, primarySqrtPrice, targetSqrtPrice);
    }

    function align() external onlyOwner nonReentrant returns (bool, uint256, uint256) {
        uint256 balance0Before = primaryPool.currency0.balanceOf(address(this));
        uint256 balance1Before = primaryPool.currency1.balanceOf(address(this));

        bytes memory response = poolManager.unlock("");
        bool isZeroForOne = abi.decode(response, (bool));

        uint256 balance0After = primaryPool.currency0.balanceOf(address(this));
        uint256 balance1After = primaryPool.currency1.balanceOf(address(this));

        if (balance0After < balance0Before || balance1After < balance1Before) revert("Losses");
        return (isZeroForOne, balance0After - balance0Before, balance1After - balance1Before);
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert("The caller is not the pool manager");

        PoolKey memory _primaryPool = primaryPool;
        PoolKey memory _targetPool = targetPool;
        (, uint160 primarySqrtPrice, uint160 targetSqrtPrice) = calcPriceRatio();

        BalanceDelta primaryDelta;
        BalanceDelta targetDelta;
        if (primarySqrtPrice < targetSqrtPrice) {
            primaryDelta = poolManager.swap(_primaryPool, SwapParams(false, type(int128).max, targetSqrtPrice), "");
            targetDelta = poolManager.swap(_targetPool, SwapParams(true, -primaryDelta.amount0(), MIN_PRICE_LIMIT), "");
            settleDeltas(false);
            return abi.encode(false);
        } else if (primarySqrtPrice > targetSqrtPrice) {
            primaryDelta = poolManager.swap(_primaryPool, SwapParams(true, type(int256).min, targetSqrtPrice), "");
            targetDelta = poolManager.swap(
                _targetPool,
                SwapParams(false, -primaryDelta.amount1(), MAX_PRICE_LIMIT),
                ""
            );
            settleDeltas(true);
            return abi.encode(true);
        } else revert("Target pool is already aligned");
    }

    function settleDeltas(bool zeroForOne) internal {
        PoolKey memory _primaryPool = primaryPool;
        if (zeroForOne) {
            uint256 token0 = SafeCast.toUint256(poolManager.currencyDelta(address(this), _primaryPool.currency0));
            uint256 token1 = SafeCast.toUint256(-poolManager.currencyDelta(address(this), _primaryPool.currency1));

            _primaryPool.currency0.take(poolManager, address(this), token0, false);
            _primaryPool.currency1.settle(poolManager, address(this), token1, false);
        } else {
            uint256 token0 = SafeCast.toUint256(-poolManager.currencyDelta(address(this), _primaryPool.currency0));
            uint256 token1 = SafeCast.toUint256(poolManager.currencyDelta(address(this), _primaryPool.currency1));
            console.log("token0 %s", token0);
            console.log("token1 %s", token1);

            _primaryPool.currency1.take(poolManager, address(this), token1, false);
            _primaryPool.currency0.settle(poolManager, address(this), token0, false);
        }
    }

    function transfer(IERC20 token, uint256 amount, address to) external onlyOwner {
        if (address(token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            token.safeTransfer(to, amount);
        }
    }

    receive() external payable {}
}
