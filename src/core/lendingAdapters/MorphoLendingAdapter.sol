// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

// ** Morpho imports
import {IMorpho, Id, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";

// ** libraries
import {TokenWrapperLib} from "@src/libraries/TokenWrapperLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ** contracts
import {Base} from "@src/core/base/Base.sol";

// ** interfaces
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingAdapter, IFlashLoanReceiver} from "@src/interfaces/ILendingAdapter.sol";

contract MorphoLendingAdapter is Base, ILendingAdapter {
    error NotInBorrowMode();

    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** Morpho
    IMorpho constant morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    Id public immutable longMId;
    Id public immutable shortMId;
    IERC4626 public immutable earnQuote;
    IERC4626 public immutable earnBase;
    bool public immutable isEarn;

    constructor(Id _longMId, Id _shortMId, address _earnBase, address _earnQuote) Base(msg.sender) {
        if (_earnQuote != address(0)) {
            isEarn = true;
            earnQuote = IERC4626(_earnQuote);
            earnBase = IERC4626(_earnBase);
        } else {
            isEarn = false;
            longMId = _longMId;
            shortMId = _shortMId;
        }
    }

    function _postSetTokens() internal override {
        IERC20(base).forceApprove(address(morpho), type(uint256).max);
        IERC20(quote).forceApprove(address(morpho), type(uint256).max);
        if (isEarn) {
            IERC20(base).forceApprove(address(earnBase), type(uint256).max);
            IERC20(quote).forceApprove(address(earnQuote), type(uint256).max);
        }
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
        require(msg.sender == address(morpho), "M0");
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, address asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, address, uint256, bytes)
            );
            IERC20(asset).safeTransfer(sender, amount);

            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            IERC20(asset).safeTransferFrom(sender, address(this), amount);
        } else if (loanType == 1) {
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
            IERC20(asset1).safeTransferFrom(sender, address(this), amount1);
        } else if (loanType == 2) {
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

            morpho.flashLoan(asset1, amount1, __data);
            IERC20(asset0).safeTransferFrom(sender, address(this), amount0);
        } else revert("M2");

        return "";
    }

    // ** Long market

    function getBorrowedLong() external view returns (uint256) {
        if (isEarn) return 0;
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(longMId), address(this)).wrap(bDec);
    }

    function getCollateralLong() external view returns (uint256) {
        if (isEarn) return earnQuote.convertToAssets(earnQuote.balanceOf(address(this))).wrap(qDec);
        Position memory p = morpho.position(longMId, address(this));
        return uint256(p.collateral).wrap(qDec);
    }

    function borrowLong(uint256 amount) external onlyModule notPaused notShutdown isBorrowMode {
        morpho.borrow(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), msg.sender);
    }

    function repayLong(uint256 amount) external onlyModule notPaused isBorrowMode {
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        morpho.repay(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), "");
    }

    function removeCollateralLong(uint256 amount) external onlyModule notPaused {
        if (isEarn) earnQuote.withdraw(amount.unwrap(qDec), msg.sender, address(this));
        else
            morpho.withdrawCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), msg.sender);
    }

    function addCollateralLong(uint256 amount) external onlyModule notPaused notShutdown {
        IERC20(quote).safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        if (isEarn) earnQuote.deposit(amount.unwrap(qDec), address(this));
        else morpho.supplyCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), "");
    }

    // ** Short market

    function getBorrowedShort() external view returns (uint256) {
        if (isEarn) return 0;
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(shortMId), address(this)).wrap(qDec);
    }

    function getCollateralShort() external view returns (uint256) {
        if (isEarn) return earnBase.convertToAssets(earnBase.balanceOf(address(this))).wrap(bDec);
        Position memory p = morpho.position(shortMId, address(this));
        return uint256(p.collateral).wrap(bDec);
    }

    function borrowShort(uint256 amount) external onlyModule notPaused notShutdown isBorrowMode {
        morpho.borrow(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), msg.sender);
    }

    function repayShort(uint256 amount) external onlyModule notPaused isBorrowMode {
        IERC20(quote).safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        morpho.repay(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), "");
    }

    function removeCollateralShort(uint256 amount) external onlyModule notPaused {
        if (isEarn) earnBase.withdraw(amount.unwrap(bDec), msg.sender, address(this));
        else
            morpho.withdrawCollateral(
                morpho.idToMarketParams(shortMId),
                amount.unwrap(bDec),
                address(this),
                msg.sender
            );
    }

    function addCollateralShort(uint256 amount) external onlyModule notPaused notShutdown {
        IERC20(base).safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        if (isEarn) earnBase.deposit(amount.unwrap(bDec), address(this));
        else morpho.supplyCollateral(morpho.idToMarketParams(shortMId), amount.unwrap(bDec), address(this), "");
    }

    // ** Helpers

    function syncLong() external {
        if (!isEarn) morpho.accrueInterest(morpho.idToMarketParams(longMId));
    }

    function syncShort() external {
        if (!isEarn) morpho.accrueInterest(morpho.idToMarketParams(shortMId));
    }

    modifier isBorrowMode() {
        if (isEarn) revert NotInBorrowMode();
        _;
    }
}
