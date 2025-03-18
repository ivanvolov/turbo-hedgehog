// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {ISwapRouter} from "@src/interfaces/swapAdapters/ISwapRouter.sol";
import {IUniswapV3Pool} from "@src/interfaces/swapAdapters/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapV3SwapAdapter is Base, ISwapAdapter {
    using SafeERC20 for IERC20;

    address public targetPool;
    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    constructor() Base(msg.sender) {}

    function _postSetTokens() internal override {
        IERC20(base).forceApprove(SWAP_ROUTER, type(uint256).max);
        IERC20(quote).forceApprove(SWAP_ROUTER, type(uint256).max);
    }

    function setTargetPool(address _targetPool) external onlyOwner {
        targetPool = _targetPool;
    }

    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn) external onlyModule returns (uint256) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        return
            ISwapRouter(SWAP_ROUTER).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: IUniswapV3Pool(targetPool).fee(),
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external onlyModule returns (uint256 amountIn) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), IERC20(tokenIn).balanceOf(msg.sender));
        amountIn = ISwapRouter(SWAP_ROUTER).exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: IUniswapV3Pool(targetPool).fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountInMaximum: type(uint256).max,
                amountOut: amountOut,
                sqrtPriceLimitX96: 0
            })
        );

        if (IERC20(tokenIn).balanceOf(address(this)) > 0)
            IERC20(tokenIn).safeTransfer(msg.sender, IERC20(tokenIn).balanceOf(address(this)));
    }
}
