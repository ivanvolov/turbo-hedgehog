// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISwapAdapter {
    function swapExactOutput(address tokenIn, address tokenOut, uint256 amountOut) external returns (uint256);

    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256);
}
