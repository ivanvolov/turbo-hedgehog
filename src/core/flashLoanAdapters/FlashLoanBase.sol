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
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        assetReturnSelf = _assetReturnSelf;
    }

    function flashLoanSingle(IERC20 asset, uint256 amount, bytes calldata data) external onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, asset, amount, data);
        _flashLoanSingle(asset, amount, _data);
    }

    function flashLoanTwoTokens(
        IERC20 asset0,
        uint256 amount0,
        IERC20 asset1,
        uint256 amount1,
        bytes calldata data
    ) external onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(2), msg.sender, asset0, amount0, asset1, amount1, data);
        _flashLoanSingle(asset0, amount0, _data);
    }

    function _flashLoanSingle(IERC20 asset, uint256 amount, bytes memory _data) internal virtual;

    function _onFlashLoan(bytes calldata _data) internal {
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, IERC20 asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, IERC20, uint256, bytes)
            );

            asset.safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            asset.safeTransferFrom(sender, assetReturnSelf ? address(this) : msg.sender, amount);
        } else if (loanType == 2) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));
            bytes memory __data = abi.encode(uint8(1), sender, asset0, amount0, asset1, amount1, data);

            asset0.safeTransfer(sender, amount0);
            _flashLoanSingle(asset1, amount1, __data);
            asset0.safeTransferFrom(sender, assetReturnSelf ? address(this) : msg.sender, amount0);
        } else if (loanType == 1) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));

            asset1.safeTransfer(sender, amount1);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            asset1.safeTransferFrom(sender, assetReturnSelf ? address(this) : msg.sender, amount1);
        } else revert NotAllowedLoanType(loanType);
    }
}
