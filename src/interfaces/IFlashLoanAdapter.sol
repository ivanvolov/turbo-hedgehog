// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** external imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Defines the interface for a Flash Loan Adapter.
interface IFlashLoanAdapter {
    function flashLoanSingle(bool isBase, uint256 amount, bytes calldata data) external;

    function flashLoanTwoTokens(uint256 amountBase, uint256 amountQuote, bytes calldata data) external;
}

/// @notice Defines the interface for a Flash Loan Receiver.
interface IFlashLoanReceiver {
    function onFlashLoanSingle(bool isBase, uint256 amount, bytes calldata data) external;

    function onFlashLoanTwoTokens(uint256 amountBase, uint256 amountQuote, bytes calldata data) external;
}
