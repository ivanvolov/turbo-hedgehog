// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {ISwapAdapter} from "@src/interfaces/ISwapAdapter.sol";
import {ISwapRouter} from "@src/interfaces/swapAdapters/ISwapRouter.sol";
import {IUniswapV3Pool} from "@src/interfaces/swapAdapters/IUniswapV3Pool.sol";

contract UniswapV3SwapAdapter is Base, ISwapAdapter {
    using SafeERC20 for IERC20;

    IUniswapV3Pool public targetPool;
    ISwapRouter immutable SWAP_ROUTER;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        ISwapRouter swapRouter
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        SWAP_ROUTER = swapRouter;

        base.forceApprove(address(SWAP_ROUTER), type(uint256).max);
        quote.forceApprove(address(SWAP_ROUTER), type(uint256).max);
    }

    function setTargetPool(IUniswapV3Pool _targetPool) external onlyOwner {
        targetPool = _targetPool;
    }

    function swapExactInput(IERC20 tokenIn, IERC20 tokenOut, uint256 amountIn) external onlyModule returns (uint256) {
        if (amountIn == 0) return 0;
        tokenIn.safeTransferFrom(msg.sender, address(this), amountIn);
        return
            SWAP_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(tokenIn),
                    tokenOut: address(tokenOut),
                    fee: targetPool.fee(),
                    recipient: msg.sender,
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function swapExactOutput(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountOut
    ) external onlyModule returns (uint256 amountIn) {
        if (amountOut == 0) return 0;
        tokenIn.safeTransferFrom(msg.sender, address(this), tokenIn.balanceOf(msg.sender));
        amountIn = SWAP_ROUTER.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: address(tokenIn),
                tokenOut: address(tokenOut),
                fee: targetPool.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountInMaximum: type(uint256).max,
                amountOut: amountOut,
                sqrtPriceLimitX96: 0
            })
        );

        if (tokenIn.balanceOf(address(this)) > 0) tokenIn.safeTransfer(msg.sender, tokenIn.balanceOf(address(this)));
    }
}
