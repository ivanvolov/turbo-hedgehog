// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {IPositionManager} from "../../interfaces/IPositionManager.sol";

/// @title Unicord Position Manager
/// @notice Holds rehypothecation flow for position adjustment, then price moves up or down. Calculates swap fees.
contract UnicordPositionManager is Base, IPositionManager {
    event FeesSet(uint24 newFees);

    using SafeERC20 for IERC20;

    /// @notice The fee taken from the input amount, expressed in hundredths of a bip.
    uint24 fees;

    constructor(IERC20 _base, IERC20 _quote) Base(ComponentType.POSITION_MANAGER, msg.sender, _base, _quote) {
        // Intentionally empty as all initialization is handled by the parent Base contract
    }

    /// @notice the swap fee is represented in hundredths of a bip, so the max is 100%
    uint24 internal constant MAX_SWAP_FEE = 1e6;

    function setFees(uint24 _fees) external onlyOwner {
        if (_fees > MAX_SWAP_FEE) revert ProtocolFeeTooLarge(_fees);
        fees = _fees;
        emit FeesSet(_fees);
    }

    function positionAdjustmentPriceUp(uint256 deltaBase, uint256 deltaQuote) external onlyALM onlyActive {
        BASE.safeTransferFrom(address(alm), address(this), deltaBase);
        lendingAdapter.updatePosition(SafeCast.toInt256(deltaQuote), -SafeCast.toInt256(deltaBase), 0, 0);
        QUOTE.safeTransfer(address(alm), deltaQuote);
    }

    function positionAdjustmentPriceDown(uint256 deltaBase, uint256 deltaQuote) external onlyALM onlyActive {
        QUOTE.safeTransferFrom(address(alm), address(this), deltaQuote);
        lendingAdapter.updatePosition(-SafeCast.toInt256(deltaQuote), SafeCast.toInt256(deltaBase), 0, 0);
        BASE.safeTransfer(address(alm), deltaBase);
    }

    function getSwapFees(bool, int256) external view returns (uint24) {
        return fees;
    }
}
