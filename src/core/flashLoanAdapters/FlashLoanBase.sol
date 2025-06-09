// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {IFlashLoanAdapter, IFlashLoanReceiver} from "../../interfaces/IFlashLoanAdapter.sol";

abstract contract FlashLoanBase is Base, IFlashLoanAdapter {
    error NotAllowedLoanType(uint8 loanType);

    using SafeERC20 for IERC20;

    bool public immutable assetReturnSelf;

    constructor(
        bool _assetReturnSelf,
        IERC20 _base,
        IERC20 _quote
    ) Base(ComponentType.EXTERNAL_ADAPTER, msg.sender, _base, _quote) {
        assetReturnSelf = _assetReturnSelf;
    }

    function flashLoanSingle(bool isBase, uint256 amount, bytes calldata data) external onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, isBase, amount, data);
        _flashLoanSingle(isBase, amount, _data);
    }

    function flashLoanTwoTokens(
        uint256 amountBase,
        uint256 amountQuote,
        bytes calldata data
    ) external onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(2), msg.sender, amountBase, amountQuote, data);
        _flashLoanSingle(true, amountBase, _data);
    }

    function _flashLoanSingle(bool isBase, uint256 amount, bytes memory _data) internal virtual;

    function _onFlashLoan(bytes calldata _data) internal {
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, bool isBase, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, bool, uint256, bytes)
            );
            IERC20 asset = isBase ? BASE : QUOTE;

            asset.safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(isBase, amount, data);
            asset.safeTransferFrom(sender, assetReturnSelf ? address(this) : msg.sender, amount);
        } else if (loanType == 2) {
            (, address sender, uint256 amountBase, uint256 amountQuote, bytes memory data) = abi.decode(
                _data,
                (uint8, address, uint256, uint256, bytes)
            );
            bytes memory __data = abi.encode(uint8(1), sender, amountBase, amountQuote, data);

            BASE.safeTransfer(sender, amountBase);
            _flashLoanSingle(false, amountQuote, __data);
            BASE.safeTransferFrom(sender, assetReturnSelf ? address(this) : msg.sender, amountBase);
        } else if (loanType == 1) {
            (, address sender, uint256 amountBase, uint256 amountQuote, bytes memory data) = abi.decode(
                _data,
                (uint8, address, uint256, uint256, bytes)
            );

            QUOTE.safeTransfer(sender, amountQuote);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(amountBase, amountQuote, data);
            QUOTE.safeTransferFrom(sender, assetReturnSelf ? address(this) : msg.sender, amountQuote);
        } else revert NotAllowedLoanType(loanType);
    }
}
