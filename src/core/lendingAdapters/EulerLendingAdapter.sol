// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Euler imports
import {IEulerVault} from "../../interfaces/lendingAdapters/IEulerVault.sol";
import {IEVC} from "../../interfaces/lendingAdapters/IEVC.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {TokenWrapperLib} from "../../libraries/TokenWrapperLib.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {ILendingAdapter, IFlashLoanReceiver} from "../../interfaces/ILendingAdapter.sol";

contract EulerLendingAdapter is Base, ILendingAdapter {
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** EulerV2
    IEVC immutable evc;
    IEulerVault public immutable vault0;
    IEulerVault public immutable vault1;
    IEulerVault public immutable flVault0;
    IEulerVault public immutable flVault1;
    address public immutable subAccount0 = getSubAccountAddress(1);
    address public immutable subAccount1 = getSubAccountAddress(2);
    address public immutable flVault0Asset;
    address public immutable flVault1Asset;

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        IEVC _evc,
        IEulerVault _vault0,
        IEulerVault _vault1,
        IEulerVault _flVault0,
        IEulerVault _flVault1
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        evc = _evc;
        vault0 = _vault0;
        vault1 = _vault1;
        flVault0 = _flVault0;
        flVault1 = _flVault1;

        flVault0Asset = flVault0.asset();
        flVault1Asset = flVault1.asset();

        evc.enableController(subAccount0, address(vault0));
        evc.enableCollateral(subAccount0, address(vault1));
        evc.enableController(subAccount1, address(vault1));
        evc.enableCollateral(subAccount1, address(vault0));

        base.forceApprove(address(vault0), type(uint256).max);
        quote.forceApprove(address(vault0), type(uint256).max);
        base.forceApprove(address(vault1), type(uint256).max);
        quote.forceApprove(address(vault1), type(uint256).max);
    }

    function getSubAccountAddress(uint8 accountId) internal view returns (address) {
        return address(uint160(address(this)) ^ uint160(accountId));
    }

    // ---- Flashloan ----

    function flashLoanSingle(IERC20 asset, uint256 amount, bytes calldata data) public onlyModule notPaused {
        bytes memory _data = abi.encode(0, msg.sender, asset, amount, data);
        getVaultByToken(asset).flashLoan(amount, _data);
    }

    function flashLoanTwoTokens(
        IERC20 asset0,
        uint256 amount0,
        IERC20 asset1,
        uint256 amount1,
        bytes calldata data
    ) public onlyModule notPaused {
        bytes memory _data = abi.encode(2, msg.sender, asset0, amount0, asset1, amount1, data);
        getVaultByToken(asset0).flashLoan(amount0, _data);
    }

    function onFlashLoan(bytes calldata _data) external notPaused returns (bytes32) {
        require(msg.sender == address(flVault0) || msg.sender == address(flVault1), "M0");
        uint8 loanType = abi.decode(_data, (uint8));

        if (loanType == 0) {
            (, address sender, IERC20 asset, uint256 amount, bytes memory data) = abi.decode(
                _data,
                (uint8, address, IERC20, uint256, bytes)
            );

            asset.safeTransfer(sender, amount);
            IFlashLoanReceiver(sender).onFlashLoanSingle(asset, amount, data);
            asset.safeTransferFrom(sender, msg.sender, amount);
        } else if (loanType == 2) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));
            bytes memory __data = abi.encode(uint8(1), sender, asset0, amount0, asset1, amount1, data);

            asset0.safeTransfer(sender, amount0);
            getVaultByToken(asset1).flashLoan(amount1, __data);
            asset0.safeTransferFrom(sender, msg.sender, amount0);
        } else if (loanType == 1) {
            (, address sender, IERC20 asset0, uint256 amount0, IERC20 asset1, uint256 amount1, bytes memory data) = abi
                .decode(_data, (uint8, address, IERC20, uint256, IERC20, uint256, bytes));

            asset1.safeTransfer(sender, amount1);
            IFlashLoanReceiver(sender).onFlashLoanTwoTokens(asset0, amount0, asset1, amount1, data);
            asset1.safeTransferFrom(sender, msg.sender, amount1);
        } else revert("M2");

        return "";
    }

    function getVaultByToken(IERC20 token) public view returns (IEulerVault) {
        if (flVault0Asset == address(token)) return flVault0;
        else if (flVault1Asset == address(token)) return flVault1;
        else revert("M1");
    }

    // ---- Long market ----

    function getBorrowedLong() external view returns (uint256) {
        return vault0.debtOf(subAccount0).wrap(bDec);
    }

    function getCollateralLong() external view returns (uint256) {
        return vault1.convertToAssets(vault1.balanceOf(subAccount0)).wrap(qDec);
    }

    function borrowLong(uint256 amount) external onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(bDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayLong(uint256 amount) external onlyModule notPaused {
        base.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.repay(amount.unwrap(bDec), subAccount0);
    }

    function removeCollateralLong(uint256 amount) external onlyModule notPaused {
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
        quote.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.mint(vault1.convertToShares(amount.unwrap(qDec)), subAccount0);
    }

    // ---- Short market ----

    function getBorrowedShort() external view returns (uint256) {
        return vault1.debtOf(subAccount1).wrap(qDec);
    }

    function getCollateralShort() external view returns (uint256) {
        return vault0.convertToAssets(vault0.balanceOf(subAccount1)).wrap(bDec);
    }

    function borrowShort(uint256 amount) external onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(qDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayShort(uint256 amount) external onlyModule notPaused {
        quote.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.repay(amount.unwrap(qDec), subAccount1);
    }

    function removeCollateralShort(uint256 amount) external onlyModule notPaused {
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
        base.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.mint(vault0.convertToShares(amount.unwrap(bDec)), subAccount1);
    }

    // ---- Helpers ----

    function syncLong() external {
        // Intentionally empty as no synchronization is needed for long positions
    }

    function syncShort() external {
        // Intentionally empty as no synchronization is needed for short positions
    }
}
