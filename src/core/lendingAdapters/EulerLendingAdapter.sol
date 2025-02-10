// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** Euler imports
import {IEulerVault} from "@forks/euler/IVault.sol";
import {IEVC} from "@forks/euler/IEVC.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

contract EulerLendingAdapter is Base, ILendingAdapter {
    using TokenWrapperLib for uint256;

    // ** EulerV2
    IEVC evc = IEVC(0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383);
    IEulerVault vault0;
    IEulerVault vault1;
    address public subAccount0 = getSubAccountAddress(1);
    address public subAccount1 = getSubAccountAddress(2);

    constructor(address _vault0, address _vault1) Base(msg.sender) {
        vault0 = IEulerVault(_vault0);
        vault1 = IEulerVault(_vault1);

        evc.enableController(subAccount0, address(vault0));
        evc.enableCollateral(subAccount0, address(vault1));
        evc.enableController(subAccount1, address(vault1));
        evc.enableCollateral(subAccount1, address(vault0));
    }

    // @Notice: baseToken is name token0, and quoteToken is name token1
    function _postSetTokens() internal override {
        IERC20(token0).approve(address(vault0), type(uint256).max);
        IERC20(token1).approve(address(vault0), type(uint256).max);
        IERC20(token0).approve(address(vault1), type(uint256).max);
        IERC20(token1).approve(address(vault1), type(uint256).max);
    }

    function getSubAccountAddress(uint8 accountId) public view returns (address) {
        require(accountId < 256, "Invalid account ID");
        // XOR the last byte of the address with the account ID
        return address(uint160(address(this)) ^ uint160(accountId));
    }

    // ** Long market

    function getBorrowedLong() external view returns (uint256) {
        return vault0.debtOf(subAccount0).wrap(t0Dec);
    }

    function getCollateralLong() external view returns (uint256) {
        return vault1.convertToAssets(vault1.balanceOf(subAccount0)).wrap(t1Dec);
    }

    function borrowLong(uint256 amount) external onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        console.log("amount.unwrap(t0Dec) %s", amount.unwrap(t0Dec));
        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(t0Dec), msg.sender))
        });
        evc.batch(items);
    }

    function repayLong(uint256 amount) external onlyModule notPaused {
        IERC20(token0).transferFrom(msg.sender, address(this), amount.unwrap(t0Dec));
        vault0.repay(amount.unwrap(t0Dec), subAccount0);
    }

    function removeCollateralLong(uint256 amount) external onlyModule notPaused {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(t1Dec), msg.sender, subAccount0))
        });
        evc.batch(items);
    }

    function addCollateralLong(uint256 amount) external onlyModule notPaused notShutdown {
        IERC20(token1).transferFrom(msg.sender, address(this), amount.unwrap(t1Dec));
        vault1.mint(vault1.convertToShares(amount.unwrap(t1Dec)), subAccount0);
    }

    // ** Short market

    function getBorrowedShort() external view returns (uint256) {
        return vault1.debtOf(subAccount1).wrap(t1Dec);
    }

    function getCollateralShort() external view returns (uint256) {
        return vault0.convertToAssets(vault0.balanceOf(subAccount1)).wrap(t0Dec);
    }

    function borrowShort(uint256 amount) external onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        console.log("amount.unwrap(t1Dec) %s", amount.unwrap(t1Dec));
        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(t1Dec), msg.sender))
        });
        evc.batch(items);
    }

    function repayShort(uint256 amount) external onlyModule notPaused {
        IERC20(token1).transferFrom(msg.sender, address(this), amount.unwrap(t1Dec));
        vault1.repay(amount.unwrap(t1Dec), subAccount1);
    }

    function removeCollateralShort(uint256 amount) external onlyModule notPaused {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(t0Dec), msg.sender, subAccount1))
        });
        evc.batch(items);
    }

    function addCollateralShort(uint256 amount) external onlyModule notPaused notShutdown {
        IERC20(token0).transferFrom(msg.sender, address(this), amount.unwrap(t0Dec));
        vault0.mint(vault0.convertToShares(amount.unwrap(t0Dec)), subAccount1);
    }

    // ** Helpers

    function syncLong() external {}

    function syncShort() external {}
}
