// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// ** External imports
import {ud} from "@prb-math/UD60x18.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** contracts
import {Base} from "../Base/Base.sol";

// ** interfaces
import {IPositionManager} from "../../interfaces/IPositionManager.sol";

/// @title Position Manager
/// @notice Holds flow for position adjustment, then the price moves up or down. Calculates swap fees.
contract PositionManager is Base, IPositionManager {
    event KParamsSet(uint256 newK1, uint256 newK2);

    using SafeERC20 for IERC20;

    uint256 public k1;
    uint256 public k2;

    constructor(IERC20 _base, IERC20 _quote) Base(ComponentType.POSITION_MANAGER, msg.sender, _base, _quote) {
        // Intentionally empty as all initialization is handled by the parent Base contract
    }

    function setKParams(uint256 _k1, uint256 _k2) external onlyOwner {
        k1 = _k1;
        k2 = _k2;

        emit KParamsSet(_k1, _k2);
    }

    uint256 constant WAD = 1e18;

    function positionAdjustmentPriceUp(
        uint256 deltaBase,
        uint256 deltaQuote,
        uint160 sqrtPrice
    ) external onlyALM onlyActive {
        BASE.safeTransferFrom(address(alm), address(this), deltaBase);

        uint256 k = sqrtPrice >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Repay dUSD of long debt;
        // Remove k * dETH from long collateral;
        // Repay (k-1) * dETH to short debt;

        uint256 updateAmount = ud(k).mul(ud(deltaQuote)).unwrap();
        lendingAdapter.updatePosition(SafeCast.toInt256(updateAmount), 0, -SafeCast.toInt256(deltaBase), 0);
        if (k != WAD) lendingAdapter.repayShort(updateAmount - deltaQuote);

        QUOTE.safeTransfer(address(alm), deltaQuote);
    }

    function positionAdjustmentPriceDown(
        uint256 deltaBase,
        uint256 deltaQuote,
        uint160 sqrtPrice
    ) external onlyALM onlyActive {
        QUOTE.safeTransferFrom(address(alm), address(this), deltaQuote);

        uint256 k = sqrtPrice >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Add k1 * dETH to long as collateral;
        // Borrow (k1-1) * dETH from short by increasing debt;
        // Borrow dUSD from long by increasing debt;

        lendingAdapter.addCollateralLong(deltaQuote);
        if (k != WAD) {
            uint256 updateAmount = ud(k - WAD).mul(ud(deltaQuote)).unwrap();
            lendingAdapter.borrowShort(updateAmount);
            lendingAdapter.addCollateralLong(updateAmount);
        }
        lendingAdapter.borrowLong(deltaBase);

        BASE.safeTransfer(address(alm), deltaBase);
    }
}
