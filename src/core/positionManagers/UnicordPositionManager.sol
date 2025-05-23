// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {TokenWrapperLib} from "../../libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {IPositionManager} from "../../interfaces/IPositionManager.sol";

/// @title UnicordPositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract UnicordPositionManager is Base, IPositionManager {
    event FeesSet(uint256 newFees);

    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    uint256 fees;

    constructor(IERC20 _base, IERC20 _quote, uint8 _bDec, uint8 _qDec) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        // Intentionally empty as all initialization is handled by the parent Base contract
    }

    function setFees(uint256 _fees) external onlyOwner {
        fees = _fees;
        emit FeesSet(_fees);
    }

    function positionAdjustmentPriceUp(uint256 deltaBase, uint256 deltaQuote) external onlyALM notPaused notShutdown {
        BASE.safeTransferFrom(address(alm), address(this), deltaBase.unwrap(bDec));
        lendingAdapter.updatePosition(SafeCast.toInt256(deltaQuote), -SafeCast.toInt256(deltaBase), 0, 0);
        QUOTE.safeTransfer(address(alm), deltaQuote.unwrap(qDec));
    }

    function positionAdjustmentPriceDown(uint256 deltaBase, uint256 deltaQuote) external onlyALM notPaused notShutdown {
        QUOTE.safeTransferFrom(address(alm), address(this), deltaQuote.unwrap(qDec));
        lendingAdapter.updatePosition(-SafeCast.toInt256(deltaQuote), SafeCast.toInt256(deltaBase), 0, 0);
        BASE.safeTransfer(address(alm), deltaBase.unwrap(bDec));
    }

    function getSwapFees(bool, int256) external view returns (uint256) {
        return fees;
    }
}
