// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoanAdapter {
    // ** Flashloan
    function flashLoanSingle(IERC20 token, uint256 amount, bytes calldata data) external;

    function flashLoanTwoTokens(
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1,
        bytes calldata data
    ) external;
}

interface IFlashLoanReceiver {
    function onFlashLoanSingle(IERC20 token, uint256 amount, bytes calldata data) external;

    function onFlashLoanTwoTokens(
        IERC20 token0,
        uint256 amount0,
        IERC20 token1,
        uint256 amount1,
        bytes calldata data
    ) external;
}
