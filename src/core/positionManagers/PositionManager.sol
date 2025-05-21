// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {PRBMathUD60x18} from "@prb-math/PRBMathUD60x18.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {TokenWrapperLib} from "../../libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "../Base/Base.sol";

// ** interfaces
import {IPositionManager} from "../../interfaces/IPositionManager.sol";

/// @title PositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract PositionManager is Base, IPositionManager {
    event KParamsSet(uint256 newK1, uint256 newK2);
    event FeesSet(uint256 newFees);

    using PRBMathUD60x18 for uint256;
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    uint256 public k1;
    uint256 public k2;

    uint256 fees;

    constructor(IERC20 _base, IERC20 _quote, uint8 _bDec, uint8 _qDec) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        // Intentionally empty as all initialization is handled by the parent Base contract
    }

    function setKParams(uint256 _k1, uint256 _k2) external onlyOwner {
        k1 = _k1;
        k2 = _k2;

        emit KParamsSet(_k1, _k2);
    }

    function setFees(uint256 _fees) external onlyOwner {
        fees = _fees;
        emit FeesSet(_fees);
    }

    function positionAdjustmentPriceUp(uint256 deltaBase, uint256 deltaQuote) external onlyALM notPaused notShutdown {
        base.safeTransferFrom(address(alm), address(this), deltaBase.unwrap(bDec));

        uint256 k = alm.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Repay dUSD of long debt;
        // Remove k * dETH from long collateral;
        // Repay (k-1) * dETH to short debt;

        lendingAdapter.updatePosition(SafeCast.toInt256(k.mul(deltaQuote)), 0, -SafeCast.toInt256(deltaBase), 0);

        if (k != 1e18) lendingAdapter.repayShort((k - 1e18).mul(deltaQuote));

        quote.safeTransfer(address(alm), deltaQuote.unwrap(qDec));
    }

    function positionAdjustmentPriceDown(uint256 deltaBase, uint256 deltaQuote) external onlyALM notPaused notShutdown {
        quote.safeTransferFrom(address(alm), address(this), deltaQuote.unwrap(qDec));

        uint256 k = alm.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Add k1 * dETH to long as collateral;
        // Borrow (k1-1) * dETH from short by increasing debt;
        // Borrow dUSD from long by increasing debt;
        lendingAdapter.addCollateralLong(deltaQuote);

        if (k != 1e18) {
            lendingAdapter.borrowShort((k - 1e18).mul(deltaQuote));
            lendingAdapter.addCollateralLong((k - 1e18).mul(deltaQuote));
        }
        lendingAdapter.borrowLong(deltaBase);

        base.safeTransfer(address(alm), deltaBase.unwrap(bDec));
    }

    function getSwapFees(bool, int256) external view returns (uint256) {
        return fees;
    }
}
