// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapAdapter {
    function swapExactOutput(IERC20 tokenIn, IERC20 tokenOut, uint256 amountOut) external returns (uint256);

    function swapExactInput(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) external returns (uint256);
}
