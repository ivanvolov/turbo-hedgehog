// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/console.sol";

// ** Morpho imports
import {IMorpho, Id, Position} from "@forks/morpho/IMorpho.sol";
import {MorphoBalancesLib} from "@forks/morpho/libraries/MorphoBalancesLib.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILendingAdapter, IFlashLoanReceiver} from "@src/interfaces/ILendingAdapter.sol";

contract MorphoLendingAdapter is Base, ILendingAdapter {
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** Morpho
    IMorpho public constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    Id longMId;
    Id shortMId;

    constructor(Id _longMId, Id _shortMId) Base(msg.sender) {
        longMId = _longMId;
        shortMId = _shortMId;
    }

    function _postSetTokens() internal override {
        IERC20(base).forceApprove(address(morpho), type(uint256).max);
        IERC20(quote).forceApprove(address(morpho), type(uint256).max);
    }

    // ** Flashloan

    function flashLoanSingle(address asset, uint256 amount, bytes calldata data) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, asset, amount, data);
        morpho.flashLoan(asset, amount, _data);
    }

    function flashLoanTwoTokens(
        address asset0,
        uint256 amount0,
        address asset1,
        uint256 amount1,
        bytes calldata data
    ) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(2), msg.sender, asset0, amount0, asset1, amount1, data);
        morpho.flashLoan(asset0, amount0, _data);
    }

    function onMorphoFlashLoan(uint256, bytes calldata _data) external notPaused returns (bytes32) {
        console.log("onFlashLoan");
        require(msg.sender == address(morpho), "M0");

        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, address asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, address, uint256, bytes)
            );
            IERC20(asset).safeTransfer(sender, amount);
            console.log(asset);
            console.log(amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            IERC20(asset).safeTransferFrom(sender, address(this), amount);
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
            console.log(asset1);
            console.log(amount1);
            morpho.flashLoan(asset1, amount1, __data);
            IERC20(asset0).safeTransferFrom(sender, address(this), amount0);
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
            console.log(asset0);
            console.log(amount0);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            IERC20(asset1).safeTransferFrom(sender, address(this), amount1);
        } else revert("M2");

        return "";
    }

    // ** Long market

    function getBorrowedLong() external view returns (uint256) {
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(longMId), address(this)).wrap(bDec);
    }

    function getCollateralLong() external view returns (uint256) {
        Position memory p = morpho.position(longMId, address(this));
        return uint256(p.collateral).wrap(qDec);
    }

    function borrowLong(uint256 amount) external onlyModule notPaused notShutdown {
        console.log("borrowLong %s", amount.unwrap(bDec));
        morpho.borrow(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), msg.sender);
    }

    function repayLong(uint256 amount) external onlyModule notPaused {
        console.log("repayLong %s", amount.unwrap(bDec));
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        morpho.repay(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), "");
    }

    function removeCollateralLong(uint256 amount) external onlyModule notPaused {
        console.log("removeCollateralLong %s", amount.unwrap(qDec));
        morpho.withdrawCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), msg.sender);
    }

    function addCollateralLong(uint256 amount) external onlyModule notPaused notShutdown {
        console.log("addCollateralLong %s", amount.unwrap(qDec));
        IERC20(quote).safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        morpho.supplyCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), "");
    }

    // ** Short market

    function getBorrowedShort() external view returns (uint256) {
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(shortMId), address(this)).wrap(qDec);
    }

    function getCollateralShort() external view returns (uint256) {
        Position memory p = morpho.position(shortMId, address(this));
        return uint256(p.collateral).wrap(bDec);
    }

    function borrowShort(uint256 amount) external onlyModule notPaused notShutdown {
        console.log("borrowShort %s", amount.unwrap(qDec));
        morpho.borrow(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), msg.sender);
    }

    function repayShort(uint256 amount) external onlyModule notPaused {
        console.log("repayShort %s", amount.unwrap(qDec));
        IERC20(quote).safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        morpho.repay(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), "");
    }

    function removeCollateralShort(uint256 amount) external onlyModule notPaused {
        console.log("removeCollateralShort %s", amount.unwrap(bDec));
        morpho.withdrawCollateral(morpho.idToMarketParams(shortMId), amount.unwrap(bDec), address(this), msg.sender);
    }

    function addCollateralShort(uint256 amount) external onlyModule notPaused notShutdown {
        console.log("addCollateralShort %s", amount.unwrap(bDec));
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        morpho.supplyCollateral(morpho.idToMarketParams(shortMId), amount.unwrap(bDec), address(this), "");
    }

    // ** Helpers

    function syncLong() external {
        morpho.accrueInterest(morpho.idToMarketParams(longMId));
    }

    function syncShort() external {
        morpho.accrueInterest(morpho.idToMarketParams(shortMId));
    }
}

// TODO: remove in production
// LINKS: https://docs.morpho.org/morpho/tutorials/manage-positions
