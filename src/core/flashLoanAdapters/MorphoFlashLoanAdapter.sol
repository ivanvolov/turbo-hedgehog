// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Morpho imports
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {IFlashLoanAdapter, IFlashLoanReceiver} from "../../interfaces/IFlashLoanAdapter.sol";

contract MorphoFlashLoanAdapter is Base, IFlashLoanAdapter {
    using SafeERC20 for IERC20;

    // ** Morpho
    IMorpho immutable morpho;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        IMorpho _morpho
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        morpho = _morpho;

        base.forceApprove(address(morpho), type(uint256).max);
        quote.forceApprove(address(morpho), type(uint256).max);
    }

    // ** Flashloan

    function flashLoanSingle(IERC20 asset, uint256 amount, bytes calldata data) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, asset, amount, data);
        morpho.flashLoan(address(asset), amount, _data);
    }

    function flashLoanTwoTokens(
        IERC20 asset0,
        uint256 amount0,
        IERC20 asset1,
        uint256 amount1,
        bytes calldata data
    ) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(2), msg.sender, asset0, amount0, asset1, amount1, data);
        morpho.flashLoan(address(asset0), amount0, _data);
    }

    function onMorphoFlashLoan(uint256, bytes calldata _data) external notPaused returns (bytes32) {
        require(msg.sender == address(morpho), "M0");
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, IERC20 asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, IERC20, uint256, bytes)
            );

            asset.safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            asset.safeTransferFrom(sender, address(this), amount);
        } else if (loanType == 2) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));
            bytes memory __data = abi.encode(uint8(1), sender, asset0, amount0, asset1, amount1, data);

            asset0.safeTransfer(sender, amount0);
            morpho.flashLoan(address(asset1), amount1, __data);
            asset0.safeTransferFrom(sender, address(this), amount0);
        } else if (loanType == 1) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));

            asset1.safeTransfer(sender, amount1);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            asset1.safeTransferFrom(sender, address(this), amount1);
        } else revert("M2");

        return "";
    }
}
