// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** libraries
import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// ** interfaces
import {IALM} from "@src/interfaces/IALM.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";

/// @title PositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract PositionManager is Ownable, IPositionManager {
    using FixedPointMathLib for uint256;
    using TokenWrapperLib for uint256;

    address public token0;
    address public token1;
    uint8 public t0Dec;
    uint8 public t1Dec;

    uint256 public k1 = 1e18 / 2;
    uint256 public k2 = 1e18 / 2;

    ILendingAdapter public lendingAdapter;

    IALM public hook;
    IRebalanceAdapter public rebalanceAdapter;

    constructor() Ownable(msg.sender) {}

    function setTokens(address _token0, address _token1, uint8 _t0Dec, uint8 _t1Dec) external onlyOwner {
        token0 = _token0;
        token1 = _token1;
        t0Dec = _t0Dec;
        t1Dec = _t1Dec;
    }

    function setLendingAdapter(address _lendingAdapter) external onlyOwner {
        ALMBaseLib.approveSingle(token0, address(lendingAdapter), _lendingAdapter, type(uint256).max); //TODO: check all approves to be safe
        ALMBaseLib.approveSingle(token1, address(lendingAdapter), _lendingAdapter, type(uint256).max);
        lendingAdapter = ILendingAdapter(_lendingAdapter);
    }

    function setHook(address _hook) external override onlyOwner {
        hook = IALM(_hook);
    }

    function setRebalanceAdapter(address _rebalanceAdapter) external onlyOwner {
        rebalanceAdapter = IRebalanceAdapter(_rebalanceAdapter);
    }

    function setKParams(uint256 _k1, uint256 _k2) external onlyOwner {
        k1 = _k1;
        k2 = _k2;
    }

    function positionAdjustmentPriceUp(uint256 delta0, uint256 delta1) external override {
        if (msg.sender != address(hook)) revert NotHook();
        IERC20(token0).transferFrom(address(hook), address(this), delta0.unwrap(t0Dec));

        uint256 k = hook.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Repay dUSD of long debt;
        // Remove k * dETH from long collateral;
        // Repay (k-1) * dETH to short debt;

        lendingAdapter.repayLong(delta0);
        lendingAdapter.removeCollateralLong(k.mul(delta1));
        // console.log("deltaWETH to repay %s", (k - 1e18).mul(delta1));

        if (k != 1e18) lendingAdapter.repayShort((k - 1e18).mul(delta1));

        IERC20(token1).transfer(address(hook), delta1.unwrap(t1Dec));
    }

    function positionAdjustmentPriceDown(uint256 delta0, uint256 delta1) external override {
        if (msg.sender != address(hook)) revert NotHook();
        IERC20(token1).transferFrom(address(hook), address(this), delta1.unwrap(t1Dec));

        uint256 k = hook.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Add k1 * dETH to long as collateral;
        // Borrow (k1-1) * dETH from short by increasing debt;
        // Borrow dUSD from long by increasing debt;

        lendingAdapter.addCollateralLong(delta1);
        if (k != 1e18) {
            lendingAdapter.borrowShort((k - 1e18).mul(delta1));
            lendingAdapter.addCollateralLong((k - 1e18).mul(delta1));
        }
        lendingAdapter.borrowLong(delta0);

        IERC20(token0).transfer(address(hook), delta0.unwrap(t0Dec));
    }
}
