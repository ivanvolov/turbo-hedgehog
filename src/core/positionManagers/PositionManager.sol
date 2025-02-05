// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** libraries
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title PositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract PositionManager is Base, IPositionManager {
    using FixedPointMathLib for uint256;
    using TokenWrapperLib for uint256;

    uint256 public k1 = 1e18 / 2;
    uint256 public k2 = 1e18 / 2;

    uint256 public fees;

    constructor() Base(msg.sender) {}

    function setKParams(uint256 _k1, uint256 _k2) external onlyOwner {
        k1 = _k1;
        k2 = _k2;
    }

    function setFees(uint256 _fees) external onlyOwner {
        fees = _fees;
    }

    function positionAdjustmentPriceUp(uint256 delta0, uint256 delta1) external onlyALM notPaused notShutdown {
        IERC20(token0).transferFrom(address(alm), address(this), delta0.unwrap(t0Dec));

        uint256 k = alm.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Repay dUSD of long debt;
        // Remove k * dETH from long collateral;
        // Repay (k-1) * dETH to short debt;

        lendingAdapter.repayLong(delta0);
        lendingAdapter.removeCollateralLong(k.mul(delta1));
        // console.log("deltaWETH to repay %s", (k - 1e18).mul(delta1));

        if (k != 1e18) lendingAdapter.repayShort((k - 1e18).mul(delta1));

        IERC20(token1).transfer(address(alm), delta1.unwrap(t1Dec));
    }

    function positionAdjustmentPriceDown(uint256 delta0, uint256 delta1) external onlyALM notPaused notShutdown {
        IERC20(token1).transferFrom(address(alm), address(this), delta1.unwrap(t1Dec));

        uint256 k = alm.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Add k1 * dETH to long as collateral;
        // Borrow (k1-1) * dETH from short by increasing debt;
        // Borrow dUSD from long by increasing debt;

        lendingAdapter.addCollateralLong(delta1);
        if (k != 1e18) {
            lendingAdapter.borrowShort((k - 1e18).mul(delta1));
            lendingAdapter.addCollateralLong((k - 1e18).mul(delta1));
        }
        lendingAdapter.borrowLong(delta0);

        IERC20(token0).transfer(address(alm), delta0.unwrap(t0Dec));
    }

    function getSwapFees(bool, int256) external view returns (uint256) {
        return fees;
    }
}
