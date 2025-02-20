// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ** libraries
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** interfaces
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title UnicordPositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract UnicordPositionManager is Base, IPositionManager {
    using FixedPointMathLib for uint256;
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    uint256 public fees;

    constructor() Base(msg.sender) {}

    function setFees(uint256 _fees) external onlyOwner {
        fees = _fees;
    }

    function positionAdjustmentPriceUp(uint256 deltaBase, uint256 deltaQuote) external onlyALM notPaused notShutdown {
        IERC20(base).safeTransferFrom(address(alm), address(this), deltaBase.unwrap(bDec));

        lendingAdapter.addCollateralShort(deltaBase);
        lendingAdapter.removeCollateralLong(deltaQuote);

        IERC20(quote).safeTransfer(address(alm), deltaQuote.unwrap(qDec));
    }

    function positionAdjustmentPriceDown(uint256 deltaBase, uint256 deltaQuote) external onlyALM notPaused notShutdown {
        IERC20(quote).safeTransferFrom(address(alm), address(this), deltaQuote.unwrap(qDec));

        lendingAdapter.addCollateralLong(deltaQuote);
        lendingAdapter.removeCollateralShort(deltaBase);

        IERC20(base).safeTransfer(address(alm), deltaBase.unwrap(bDec));
    }

    function getSwapFees(bool, int256) external view returns (uint256) {
        return fees;
    }
}
