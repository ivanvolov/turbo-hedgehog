// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** external imports
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {IPositionManager} from "../../interfaces/IPositionManager.sol";

/// @title Unicord Position Manager
/// @notice Holds rehypothecation flow for position adjustment when the price moves up or down.
contract UnicordPositionManager is Base, IPositionManager {
    using SafeERC20 for IERC20;

    constructor(IERC20 _base, IERC20 _quote) Base(ComponentType.POSITION_MANAGER, msg.sender, _base, _quote) {
        // Intentionally empty as all initialization is handled by parent Base contract.
    }

    function positionAdjustmentPriceUp(uint256 deltaBase, uint256 deltaQuote, uint160) external onlyHook onlyActive {
        BASE.safeTransferFrom(address(hook), address(this), deltaBase);
        lendingAdapter.updatePosition(SafeCast.toInt256(deltaQuote), -SafeCast.toInt256(deltaBase), 0, 0);
        QUOTE.safeTransfer(address(hook), deltaQuote);
    }

    function positionAdjustmentPriceDown(uint256 deltaBase, uint256 deltaQuote, uint160) external onlyHook onlyActive {
        QUOTE.safeTransferFrom(address(hook), address(this), deltaQuote);
        lendingAdapter.updatePosition(-SafeCast.toInt256(deltaQuote), SafeCast.toInt256(deltaBase), 0, 0);
        BASE.safeTransfer(address(hook), deltaBase);
    }
}
