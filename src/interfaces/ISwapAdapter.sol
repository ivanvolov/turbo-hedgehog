// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @notice Defines the interface for a Swap Adapter.
interface ISwapAdapter {
    function swapExactOutput(bool isBaseToQuote, uint256 amountOut) external returns (uint256 amountIn);

    function swapExactInput(bool isBaseToQuote, uint256 amountIn) external returns (uint256 amountOut);
}
