// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** interfaces
import {ISwapAdapter} from "../ISwapAdapter.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";

interface IUniswapV3SwapAdapter is ISwapAdapter {
    function setTargetPool(IUniswapV3Pool _targetPool) external;
}
