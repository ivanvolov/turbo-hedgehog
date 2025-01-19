// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {ERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {FixedPointMathLib} from "@src/libraries/math/FixedPointMathLib.sol";

import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {IRebalanceAdapter} from "@src/interfaces/IRebalanceAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IALM} from "@src/interfaces/IALM.sol";

/// @title PositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract PositionManager is Ownable, IPositionManager {
    using FixedPointMathLib for uint256;

    uint256 public k1 = 1e18 / 2; //TODO: set up production values here
    uint256 public k2 = 1e18 / 2;

    IERC20 WETH = IERC20(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    ILendingAdapter public lendingAdapter;

    IALM public hook;
    IRebalanceAdapter public rebalanceAdapter;

    constructor() Ownable(msg.sender) {}

    function setLendingAdapter(address _lendingAdapter) external onlyOwner {
        if (address(lendingAdapter) != address(0)) {
            WETH.approve(address(lendingAdapter), 0);
            USDC.approve(address(lendingAdapter), 0);
        }
        lendingAdapter = ILendingAdapter(_lendingAdapter);
        WETH.approve(address(lendingAdapter), type(uint256).max);
        USDC.approve(address(lendingAdapter), type(uint256).max);
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

    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH) external override {
        if (msg.sender != address(hook)) revert NotHook();
        USDC.transferFrom(address(hook), address(this), ALMBaseLib.c18to6(deltaUSDC));

        uint256 k = hook.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Repay dUSD of long debt;
        // Remove k * dETH from long collateral;
        // Repay (k-1) * dETH to short debt;

        lendingAdapter.repayLong(deltaUSDC);

        lendingAdapter.removeCollateralLong(k.mul(deltaWETH));

        if (k != 1e18) lendingAdapter.repayShort((k - 1e18).mul(deltaWETH));

        WETH.transfer(address(hook), deltaWETH);
    }

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH) external override {
        if (msg.sender != address(hook)) revert NotHook();
        WETH.transferFrom(address(hook), address(this), deltaWETH);

        uint256 k = hook.sqrtPriceCurrent() >= rebalanceAdapter.sqrtPriceAtLastRebalance() ? k2 : k1;
        // Add k1 * dETH to long as collateral;
        // Borrow (k1-1) * dETH from short by increasing debt;
        // Borrow dUSD from long by increasing debt;

        lendingAdapter.addCollateralLong(deltaWETH);
        if (k != 1e18) {
            lendingAdapter.borrowShort((k - 1e18).mul(deltaWETH));
            lendingAdapter.addCollateralLong((k - 1e18).mul(deltaWETH));
        }
        lendingAdapter.borrowLong(deltaUSDC);

        USDC.transfer(address(hook), ALMBaseLib.c18to6(deltaUSDC));
    }
}
