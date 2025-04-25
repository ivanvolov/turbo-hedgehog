// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Morpho imports
import {IMorpho, Id, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// ** libraries
import {TokenWrapperLib} from "../../libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {ILendingAdapter, IFlashLoanReceiver} from "../../interfaces/ILendingAdapter.sol";

contract MorphoLendingAdapter is Base, ILendingAdapter {
    error NotInBorrowMode();

    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** Morpho
    IMorpho immutable morpho;
    Id public immutable longMId;
    Id public immutable shortMId;
    IERC4626 public immutable earnQuote;
    IERC4626 public immutable earnBase;
    bool public immutable isEarn;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        IMorpho _morpho,
        Id _longMId,
        Id _shortMId,
        IERC4626 _earnBase,
        IERC4626 _earnQuote
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        morpho = _morpho;

        base.forceApprove(address(morpho), type(uint256).max);
        quote.forceApprove(address(morpho), type(uint256).max);
        if (address(_earnQuote) != address(0)) {
            isEarn = true;
            earnQuote = _earnQuote;
            earnBase = _earnBase;
            base.forceApprove(address(earnBase), type(uint256).max);
            quote.forceApprove(address(earnQuote), type(uint256).max);
        } else {
            isEarn = false;
            longMId = _longMId;
            shortMId = _shortMId;
        }
    }

    // ** Position management

    function getPosition() external view returns (uint256, uint256, uint256, uint256) {
        return (getCollateralLong(), getCollateralShort(), getBorrowedLong(), getBorrowedShort());
    }

    function updatePosition(
        int256 deltaCL,
        int256 deltaCS,
        int256 deltaDL,
        int256 deltaDS
    ) external onlyModule notPaused {
        if (deltaCL > 0) addCollateralLong(uint256(deltaCL));
        if (deltaCL < 0) removeCollateralLong(uint256(-deltaCL));
        if (deltaCS > 0) addCollateralShort(uint256(deltaCS));
        if (deltaCS < 0) removeCollateralShort(uint256(-deltaCS));

        if (deltaDL < 0) repayLong(uint256(-deltaDL));
        if (deltaDL > 0) borrowLong(uint256(deltaDL));
        if (deltaDS < 0) repayShort(uint256(-deltaDS));
        if (deltaDS > 0) borrowShort(uint256(deltaDS));
    }

    // ** Flashloan

    function flashLoanSingle(IERC20 asset, uint256 amount, bytes calldata data) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(0), msg.sender, asset, amount, data);
        morpho.flashLoan(address(asset), amount, _data);
    }

    function flashLoanTwoTokens(
        IERC20 asset0,
        uint256 amount0,
        IERC20 asset1,
        uint256 amount1,
        bytes calldata data
    ) public onlyModule notPaused {
        bytes memory _data = abi.encode(uint8(2), msg.sender, asset0, amount0, asset1, amount1, data);
        morpho.flashLoan(address(asset0), amount0, _data);
    }

    function onMorphoFlashLoan(uint256, bytes calldata _data) external notPaused returns (bytes32) {
        require(msg.sender == address(morpho), "M0");
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, IERC20 asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, IERC20, uint256, bytes)
            );

            asset.safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            asset.safeTransferFrom(sender, address(this), amount);
        } else if (loanType == 2) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));
            bytes memory __data = abi.encode(uint8(1), sender, asset0, amount0, asset1, amount1, data);

            asset0.safeTransfer(sender, amount0);
            morpho.flashLoan(address(asset1), amount1, __data);
            asset0.safeTransferFrom(sender, address(this), amount0);
        } else if (loanType == 1) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));

            asset1.safeTransfer(sender, amount1);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            asset1.safeTransferFrom(sender, address(this), amount1);
        } else revert("M2");

        return "";
    }

    // ** Long market

    function getBorrowedLong() public view returns (uint256) {
        if (isEarn) return 0;
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(longMId), address(this)).wrap(bDec);
    }

    function getCollateralLong() public view returns (uint256) {
        if (isEarn) return earnQuote.convertToAssets(earnQuote.balanceOf(address(this))).wrap(qDec);
        Position memory p = morpho.position(longMId, address(this));
        return uint256(p.collateral).wrap(qDec);
    }

    function borrowLong(uint256 amount) public onlyModule notPaused notShutdown isBorrowMode {
        morpho.borrow(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), msg.sender);
    }

    function repayLong(uint256 amount) public onlyModule notPaused isBorrowMode {
        base.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        morpho.repay(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), "");
    }

    function removeCollateralLong(uint256 amount) public onlyModule notPaused {
        if (isEarn) earnQuote.withdraw(amount.unwrap(qDec), msg.sender, address(this));
        else
            morpho.withdrawCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), msg.sender);
    }

    function addCollateralLong(uint256 amount) public onlyModule notPaused notShutdown {
        quote.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        if (isEarn) earnQuote.deposit(amount.unwrap(qDec), address(this));
        else morpho.supplyCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), "");
    }

    // ** Short market

    function getBorrowedShort() public view returns (uint256) {
        if (isEarn) return 0;
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(shortMId), address(this)).wrap(qDec);
    }

    function getCollateralShort() public view returns (uint256) {
        if (isEarn) return earnBase.convertToAssets(earnBase.balanceOf(address(this))).wrap(bDec);
        Position memory p = morpho.position(shortMId, address(this));
        return uint256(p.collateral).wrap(bDec);
    }

    function borrowShort(uint256 amount) public onlyModule notPaused notShutdown isBorrowMode {
        morpho.borrow(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), msg.sender);
    }

    function repayShort(uint256 amount) public onlyModule notPaused isBorrowMode {
        quote.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        morpho.repay(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), "");
    }

    function removeCollateralShort(uint256 amount) public onlyModule notPaused {
        if (isEarn) earnBase.withdraw(amount.unwrap(bDec), msg.sender, address(this));
        else
            morpho.withdrawCollateral(
                morpho.idToMarketParams(shortMId),
                amount.unwrap(bDec),
                address(this),
                msg.sender
            );
    }

    function addCollateralShort(uint256 amount) public onlyModule notPaused notShutdown {
        base.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
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
