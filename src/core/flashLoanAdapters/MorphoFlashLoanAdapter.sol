// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** external imports
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {FlashLoanBase} from "./FlashLoanBase.sol";

/// @title Morpho Flash Loan Adapter
/// @notice Implementation of the flash loan adapter using Morpho.
contract MorphoFlashLoanAdapter is FlashLoanBase {
    error NotMorpho(address account);

    using SafeERC20 for IERC20;

    IMorpho immutable morpho;

    constructor(IERC20 _base, IERC20 _quote, IMorpho _morpho) FlashLoanBase(true, _base, _quote) {
        morpho = _morpho;
        BASE.forceApprove(address(morpho), type(uint256).max);
        QUOTE.forceApprove(address(morpho), type(uint256).max);
    }

    function onMorphoFlashLoan(uint256, bytes calldata data) external notPaused returns (bytes32) {
        if (msg.sender != address(morpho)) revert NotMorpho(msg.sender);
        _onFlashLoan(data);
        return bytes32(0);
    }

    function _flashLoanSingle(bool isBase, uint256 amount, bytes memory data) internal virtual override {
        morpho.flashLoan(isBase ? address(BASE) : address(QUOTE), amount, data);
    }
}
