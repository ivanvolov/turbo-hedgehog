// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// ** interfaces
import {ISwapRouter} from "@forks/ISwapRouter.sol";
import {IUniswapV3Pool} from "@forks/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//TODO: refactor. Remove unused variables or maybe merge with ALMMathLib or BaseContract.
library ALMBaseLib {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address constant CHAINLINK_7_DAYS_VOL = 0xF3140662cE17fDee0A6675F9a511aDbc4f394003;
    address constant CHAINLINK_30_DAYS_VOL = 0x8e604308BD61d975bc6aE7903747785Db7dE97e2;

    uint24 public constant ETH_USDC_POOL_FEE = 500;
    address public constant ETH_USDC_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter constant swapRouter = ISwapRouter(SWAP_ROUTER);

    function swapExactInput(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        return
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: ETH_USDC_POOL_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function swapExactOutput(address tokenIn, address tokenOut, uint256 amountOut) internal returns (uint256) {
        return
            swapRouter.exactOutputSingle(
                ISwapRouter.ExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: ETH_USDC_POOL_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountInMaximum: type(uint256).max,
                    amountOut: amountOut,
                    sqrtPriceLimitX96: 0
                })
            );
    }

    function approveSingle(address token, address moduleOld, address moduleNew, uint256 amount) internal {
        if (moduleOld != address(0) && moduleOld != address(this)) IERC20(token).approve(moduleOld, 0);
        if (moduleNew != address(this)) IERC20(token).approve(moduleNew, amount);
    }
}
