// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** Euler imports
import {IEulerVault} from "@src/interfaces/lendingAdapters/IEulerVault.sol";
import {IEVC} from "@src/interfaces/lendingAdapters/IEVC.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingAdapter, IFlashLoanReceiver} from "@src/interfaces/ILendingAdapter.sol";

//TODO: all errors to codes or better to libs.

contract EulerLendingAdapter is Base, ILendingAdapter {
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** EulerV2
    IEVC evc = IEVC(0x0C9a3dd6b8F28529d72d7f9cE918D493519EE383);
    IEulerVault vault0;
    IEulerVault vault1;
    IEulerVault flVault0;
    IEulerVault flVault1;
    address public subAccount0 = getSubAccountAddress(1);
    address public subAccount1 = getSubAccountAddress(2);

    constructor(address _vault0, address _vault1, address _flVault0, address _flVault1) Base(msg.sender) {
        vault0 = IEulerVault(_vault0);
        vault1 = IEulerVault(_vault1);
        flVault0 = IEulerVault(_flVault0);
        flVault1 = IEulerVault(_flVault1);

        evc.enableController(subAccount0, address(vault0));
        evc.enableCollateral(subAccount0, address(vault1));
        evc.enableController(subAccount1, address(vault1));
        evc.enableCollateral(subAccount1, address(vault0));
    }

    // @Notice: baseToken is name base, and quoteToken is name quote
    function _postSetTokens() internal override {
        IERC20(base).forceApprove(address(vault0), type(uint256).max);
        IERC20(quote).forceApprove(address(vault0), type(uint256).max);
        IERC20(base).forceApprove(address(vault1), type(uint256).max);
        IERC20(quote).forceApprove(address(vault1), type(uint256).max);
    }

    function getSubAccountAddress(uint8 accountId) public view returns (address) {
        require(accountId < 256, "Invalid account ID");
        // XOR the last byte of the address with the account ID
        return address(uint160(address(this)) ^ uint160(accountId));
    }

    // ** Flashloan

    function flashLoanSingle(address asset, uint256 amount, bytes calldata data) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, asset, amount, data);
        getVaultByToken(asset).flashLoan(amount, _data);
    }

    function flashLoanTwoTokens(
        address asset0,
        uint256 amount0,
        address asset1,
        uint256 amount1,
        bytes calldata data
    ) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(2), msg.sender, asset0, amount0, asset1, amount1, data);
        getVaultByToken(asset0).flashLoan(amount0, _data);
    }

    function onFlashLoan(bytes calldata _data) external notPaused returns (bytes32) {
        console.log("onFlashLoan");
        require(msg.sender == address(flVault0) || msg.sender == address(flVault1), "M0");

        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, address asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, address, uint256, bytes)
            );
            IERC20(asset).safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            IERC20(asset).safeTransferFrom(sender, msg.sender, amount);
        } else if (loanType == 2) {
            console.log("2");
            (
                ,
                address sender,
                address asset0,
                uint256 amount0,
                address asset1,
                uint256 amount1,
                bytes memory data
            ) = abi.decode(_data, (uint8, address, address, uint256, address, uint256, bytes));

            bytes memory __data = abi.encode(uint8(1), sender, asset0, amount0, asset1, amount1, data);
            getVaultByToken(asset1).flashLoan(amount1, __data);
            IERC20(asset0).safeTransferFrom(sender, msg.sender, amount0);
        } else if (loanType == 1) {
            console.log("1");
            (
                ,
                address sender,
                address asset0,
                uint256 amount0,
                address asset1,
                uint256 amount1,
                bytes memory data
            ) = abi.decode(_data, (uint8, address, address, uint256, address, uint256, bytes));

            IERC20(asset0).safeTransfer(sender, amount0);
            IERC20(asset1).safeTransfer(sender, amount1);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            IERC20(asset1).safeTransferFrom(sender, msg.sender, amount1);
        } else revert("M2");

        return "";
    }

    function getVaultByToken(address token) public view returns (IEulerVault) {
        if (flVault0.asset() == token) return flVault0;
        else if (flVault1.asset() == token) return flVault1;
        else revert("M1");
    }

    // ** Long market

    function getBorrowedLong() external view returns (uint256) {
        return vault0.debtOf(subAccount0).wrap(bDec);
    }

    function getCollateralLong() external view returns (uint256) {
        return vault1.convertToAssets(vault1.balanceOf(subAccount0)).wrap(qDec);
    }

    function borrowLong(uint256 amount) external onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        console.log("borrowLong %s", amount.unwrap(bDec));

        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(bDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayLong(uint256 amount) external onlyModule notPaused {
        // console.log("repayLong");
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.repay(amount.unwrap(bDec), subAccount0);
    }

    function removeCollateralLong(uint256 amount) external onlyModule notPaused {
        // console.log("removeCollateralLong");
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(qDec), msg.sender, subAccount0))
        });
        evc.batch(items);
    }

    function addCollateralLong(uint256 amount) external onlyModule notPaused notShutdown {
        // console.log("addCollateralLong");
        IERC20(quote).safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.mint(vault1.convertToShares(amount.unwrap(qDec)), subAccount0);
    }

    // ** Short market

    function getBorrowedShort() external view returns (uint256) {
        return vault1.debtOf(subAccount1).wrap(qDec);
    }

    function getCollateralShort() external view returns (uint256) {
        return vault0.convertToAssets(vault0.balanceOf(subAccount1)).wrap(bDec);
    }

    function borrowShort(uint256 amount) external onlyModule notPaused notShutdown {
        // console.log("borrowShort");
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        console.log("borrowShort %s", amount.unwrap(qDec));

        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(qDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayShort(uint256 amount) external onlyModule notPaused {
        // console.log("repayShort");
        IERC20(quote).safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.repay(amount.unwrap(qDec), subAccount1);
    }

    function removeCollateralShort(uint256 amount) external onlyModule notPaused {
        // console.log("removeCollateralShort");
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(bDec), msg.sender, subAccount1))
        });
        evc.batch(items);
    }

    function addCollateralShort(uint256 amount) external onlyModule notPaused notShutdown {
        // console.log("addCollateralShort");
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.mint(vault0.convertToShares(amount.unwrap(bDec)), subAccount1);
    }

    // ** Helpers

    function syncLong() external {}

    function syncShort() external {}
}
