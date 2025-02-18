// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** interfaces
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";

interface IUniswapV3SwapAdapter is ISwapAdapter {
    function setTargetPool(address _targetPool) external;
}
