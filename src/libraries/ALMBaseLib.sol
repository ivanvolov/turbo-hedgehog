// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//TODO: refactor. Remove unused variables or maybe merge with ALMMathLib or BaseContract.
library ALMBaseLib {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function approveSingle(address token, address moduleOld, address moduleNew, uint256 amount) internal {
        if (moduleOld != address(0) && moduleOld != address(this)) IERC20(token).approve(moduleOld, 0);
        if (moduleNew != address(this)) IERC20(token).approve(moduleNew, amount);
    }
}
