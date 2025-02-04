// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** Aave imports
import {IPool} from "@aave-core-v3/contracts/interfaces/IPool.sol";
import {IAaveOracle} from "@aave-core-v3/contracts/interfaces/IAaveOracle.sol";
import {IPoolAddressesProvider} from "@aave-core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolDataProvider} from "@aave-core-v3/contracts/interfaces/IPoolDataProvider.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

contract AaveLendingAdapter is Base, ILendingAdapter {
    using TokenWrapperLib for uint256;

    // ** AaveV3
    IPoolAddressesProvider constant provider = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);

    constructor() Base(msg.sender) {}

    // @Notice: baseToken is name token0, and quoteToken is name token1
    function _postSetTokens() internal override {
        IERC20(token0).approve(getPool(), type(uint256).max);
        IERC20(token1).approve(getPool(), type(uint256).max);
    }

    function getPool() public view returns (address) {
        return provider.getPool();
    }

    // ** Long market

    function getBorrowedLong() external view returns (uint256) {
        (, , address variableDebtTokenAddress) = getAssetAddresses(token0);
        return IERC20(variableDebtTokenAddress).balanceOf(address(this)).wrap(t0Dec);
    }

    function getCollateralLong() external view returns (uint256) {
        (address aTokenAddress, , ) = getAssetAddresses(token1);
        return IERC20(aTokenAddress).balanceOf(address(this)).wrap(t1Dec);
    }

    function borrowLong(uint256 amount) external onlyModule notPaused notShutdown {
        IPool(getPool()).borrow(token0, amount.unwrap(t0Dec), 2, 0, address(this)); // Interest rate mode: 2 = variable
        IERC20(token0).transfer(msg.sender, amount.unwrap(t0Dec));
    }

    function repayLong(uint256 amount) external onlyModule notPaused {
        IERC20(token0).transferFrom(msg.sender, address(this), amount.unwrap(t0Dec));
        IPool(getPool()).repay(token0, amount.unwrap(t0Dec), 2, address(this));
    }

    function removeCollateralLong(uint256 amount) external onlyModule notPaused {
        IPool(getPool()).withdraw(token1, amount.unwrap(t1Dec), msg.sender);
    }

    function addCollateralLong(uint256 amount) external onlyModule notPaused notShutdown {
        IERC20(token1).transferFrom(msg.sender, address(this), amount.unwrap(t1Dec));
        IPool(getPool()).supply(token1, amount.unwrap(t1Dec), address(this), 0);
    }

    // ** Short market

    function getBorrowedShort() external view returns (uint256) {
        (, , address variableDebtTokenAddress) = getAssetAddresses(token1);
        return IERC20(variableDebtTokenAddress).balanceOf(address(this)).wrap(t1Dec);
    }

    function getCollateralShort() external view returns (uint256) {
        (address aTokenAddress, , ) = getAssetAddresses(token0);
        return IERC20(aTokenAddress).balanceOf(address(this)).wrap(t0Dec);
    }

    function borrowShort(uint256 amount) external onlyModule notPaused notShutdown {
        IPool(getPool()).borrow(token1, amount.unwrap(t1Dec), 2, 0, address(this)); // Interest rate mode: 2 = variable
        IERC20(token1).transfer(msg.sender, amount.unwrap(t1Dec));
    }

    function repayShort(uint256 amount) external onlyModule notPaused {
        IERC20(token1).transferFrom(msg.sender, address(this), amount.unwrap(t1Dec));
        IPool(getPool()).repay(token1, amount.unwrap(t1Dec), 2, address(this));
    }

    function removeCollateralShort(uint256 amount) external onlyModule notPaused {
        IPool(getPool()).withdraw(token0, amount.unwrap(t0Dec), msg.sender);
    }

    function addCollateralShort(uint256 amount) external onlyModule notPaused notShutdown {
        IERC20(token0).transferFrom(msg.sender, address(this), amount.unwrap(t0Dec));
        IPool(getPool()).supply(token0, amount.unwrap(t0Dec), address(this), 0);
    }

    // ** Helpers

    function getAssetAddresses(address underlying) internal view returns (address, address, address) {
        return IPoolDataProvider(provider.getPoolDataProvider()).getReserveTokensAddresses(underlying);
    }

    function syncLong() external {}

    function syncShort() external {}
}
