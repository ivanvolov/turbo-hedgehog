// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

// ** contracts
import {FlashLoanBase} from "./FlashLoanBase.sol";
import {Base} from "../base/Base.sol";

// ** libraries
import {CurrencySettler} from "../../libraries/CurrencySettler.sol";

// ** interfaces
import {IFlashLoanAdapter, IFlashLoanReceiver} from "../../interfaces/IFlashLoanAdapter.sol";

/// @title Uniswap Flash Loan Adapter
/// @notice Implementation of the flash loan adapter using Uniswap V4.
contract UniswapFlashLoanAdapter is Base, IFlashLoanAdapter {
    using SafeERC20 for IERC20;
    using CurrencySettler for Currency;

    IPoolManager public immutable manager;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        IPoolManager _manager
    ) Base(ComponentType.EXTERNAL_ADAPTER, msg.sender, _base, _quote) {
        manager = _manager;
        BASE.forceApprove(address(manager), type(uint256).max);
        QUOTE.forceApprove(address(manager), type(uint256).max);
    }

    function flashLoanSingle(bool isBase, uint256 amount, bytes calldata data) external onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, isBase, amount, data);
        manager.unlock(_data);
    }

    function flashLoanTwoTokens(
        uint256 amountBase,
        uint256 amountQuote,
        bytes calldata data
    ) external onlyModule notPaused {
        console.log("> START: flashLoanTwoTokens");
        bytes memory _data = abi.encode(uint8(2), msg.sender, amountBase, amountQuote, data);
        manager.unlock(_data);
        console.log("> END: flashLoanTwoTokens");
    }

    function unlockCallback(bytes calldata _data) external returns (bytes memory) {
        uint8 loanType = abi.decode(_data, (uint8));
        if (loanType == 0) {
            (, address sender, bool isBase, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, bool, uint256, bytes)
            );
            IERC20 asset = isBase ? BASE : QUOTE;

            manager.take(Currency.wrap(address(asset)), sender, amount);

            IFlashLoanReceiver(sender).onFlashLoanSingle(isBase, amount, data);

            manager.sync(Currency.wrap(address(asset)));
            asset.safeTransferFrom(sender, address(manager), amount);
            manager.settle();
        } else if (loanType == 2) {
            (, address sender, uint256 amountBase, uint256 amountQuote, bytes memory data) = abi.decode(
                _data,
                (uint8, address, uint256, uint256, bytes)
            );
            manager.take(Currency.wrap(address(BASE)), sender, amountBase);
            manager.take(Currency.wrap(address(QUOTE)), sender, amountQuote);

            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(amountBase, amountQuote, data);

            BASE.safeTransferFrom(sender, address(this), amountBase);
            QUOTE.safeTransferFrom(sender, address(this), amountQuote);

            console.log("(1)");
            Currency.wrap(address(BASE)).settle(manager, address(this), amountBase, false);
            console.log("(2)");
            Currency.wrap(address(QUOTE)).settle(manager, address(this), amountQuote, false);
            console.log("(3)");
        }

        return new bytes(0);
    }

    receive() external payable {}
}
