// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** interfaces
import {ISwapAdapter} from "./ISwapAdapter.sol";

/// @notice Interface for all routes and swap path related functions.
interface IUniswapSwapAdapter is ISwapAdapter {
    function setRoutesOperator(address _routesOperator) external;

    function setSwapRoute(bool isExactInput, bool isBaseToQuote, uint256[] calldata _activeSwapPath) external;

    function setSwapPath(uint256 _swapPathId, uint8 _protocolType, bytes calldata _swapInputs) external;

    function toSwapKey(bool isExactInput, bool isBaseToQuote) external pure returns (uint8);
}
