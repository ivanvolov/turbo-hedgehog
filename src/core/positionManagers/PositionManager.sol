// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {ALMMathLib} from "@src/libraries/ALMMathLib.sol";
import {ALMBaseLib} from "@src/libraries/ALMBaseLib.sol";

import {ERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "permit2/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

import {IPositionManager} from "@src/interfaces/IPositionManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IALM} from "@src/interfaces/IALM.sol";

/// @title PositionManager
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract PositionManager is Ownable, IPositionManager {
    int256 public k1 = 1e18 / 2; //TODO: set up production values here
    int256 public k2 = 1e18 / 2;

    IERC20 WETH = IERC20(ALMBaseLib.WETH);
    IERC20 USDC = IERC20(ALMBaseLib.USDC);

    ILendingAdapter public lendingAdapter;

    IALM public hook;

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

    function setKParams(int256 _k1, int256 _k2) external onlyOwner {
        k1 = _k1;
        k2 = _k2;
    }

    function positionAdjustmentPriceUp(uint256 deltaUSDC, uint256 deltaWETH) external override {
        if (msg.sender != address(hook)) revert NotHook();
        (uint256 value0, uint256 value1) = ALMMathLib.getK2Values(k2, deltaUSDC);
        if (k2 >= 0) {
            lendingAdapter.repayLong(deltaUSDC);
            if (k2 != 0) {
                lendingAdapter.removeCollateralShort(value0);
                lendingAdapter.repayLong(value0);
            }
        } else {
            lendingAdapter.addCollateralShort(value0);
            lendingAdapter.repayLong(value1);
        }

        (value0, value1) = ALMMathLib.getK1Values(k1, deltaWETH);
        if (k1 >= 0) {
            if (k1 != 0) {
                lendingAdapter.removeCollateralLong(value0);
                lendingAdapter.repayShort(value0);
            }
            lendingAdapter.removeCollateralLong(deltaWETH);
        } else {
            lendingAdapter.removeCollateralLong(value1);
            lendingAdapter.borrowShort(value0);
        }
    }

    function positionAdjustmentPriceDown(uint256 deltaUSDC, uint256 deltaWETH) external override {
        if (msg.sender != address(hook)) revert NotHook();
    }
}
