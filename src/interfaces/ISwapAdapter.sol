// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {PoolKey} from "v4-core/types/PoolKey.sol";

interface ISwapAdapter {
    function swapExactOutput(bool isBaseToQuote, uint256 amountOut) external returns (uint256 amountIn);

    function swapExactInput(bool isBaseToQuote, uint256 amountIn) external returns (uint256 amountOut);
}
