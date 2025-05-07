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
import {ILendingAdapter} from "../../interfaces/ILendingAdapter.sol";

contract EulerLendingAdapter is Base, ILendingAdapter {
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** EulerV2
    IEVC immutable evc;
    IEulerVault public immutable vault0;
    IEulerVault public immutable vault1;
    address public immutable subAccount0 = getSubAccountAddress(1);
    address public immutable subAccount1 = getSubAccountAddress(2);

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        IEVC _evc,
        IEulerVault _vault0,
        IEulerVault _vault1
    ) Base(msg.sender, _base, _quote, _bDec, _qDec) {
        evc = _evc;
        vault0 = _vault0;
        vault1 = _vault1;

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

    // ** Position management

    function getPosition() external view returns (uint256, uint256, uint256, uint256) {
        return (getCollateralLong(), getCollateralShort(), getBorrowedLong(), getBorrowedShort());
    }

    /**
     * @notice Updates the position by adjusting collateral and debt for both long and short sides.
     * @dev The order of operations is critical to avoid "phantom under-collateralization":
     *      - Collateral is added and debt is repaid first, to ensure the account is not temporarily under-collateralized.
     *      - Now collateral is removed and debt is borrowed if needed.
     */
    function updatePosition(
        int256 deltaCL,
        int256 deltaCS,
        int256 deltaDL,
        int256 deltaDS
    ) external onlyModule notPaused {
        if (deltaCL < 0) addCollateralLong(uint256(-deltaCL));
        if (deltaCS < 0) addCollateralShort(uint256(-deltaCS));

        if (deltaDL < 0) repayLong(uint256(-deltaDL));
        if (deltaDS < 0) repayShort(uint256(-deltaDS));

        if (deltaCL > 0) removeCollateralLong(uint256(deltaCL));
        if (deltaCS > 0) removeCollateralShort(uint256(deltaCS));

        if (deltaDL > 0) borrowLong(uint256(deltaDL));
        if (deltaDS > 0) borrowShort(uint256(deltaDS));
    }

    // ** Long market

    function getBorrowedLong() public view returns (uint256) {
        return vault0.debtOf(subAccount0).wrap(bDec);
    }

    function getCollateralLong() public view returns (uint256) {
        return vault1.convertToAssets(vault1.balanceOf(subAccount0)).wrap(qDec);
    }

    function borrowLong(uint256 amount) public onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(bDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayLong(uint256 amount) public onlyModule notPaused {
        base.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.repay(amount.unwrap(bDec), subAccount0);
    }

    function removeCollateralLong(uint256 amount) public onlyModule notPaused {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(qDec), msg.sender, subAccount0))
        });
        evc.batch(items);
    }

    function addCollateralLong(uint256 amount) public onlyModule notPaused notShutdown {
        quote.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.mint(vault1.convertToShares(amount.unwrap(qDec)), subAccount0);
    }

    // ** Short market

    function getBorrowedShort() public view returns (uint256) {
        return vault1.debtOf(subAccount1).wrap(qDec);
    }

    function getCollateralShort() public view returns (uint256) {
        return vault0.convertToAssets(vault0.balanceOf(subAccount1)).wrap(bDec);
    }

    function borrowShort(uint256 amount) public onlyModule notPaused notShutdown {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);

        items[0] = IEVC.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(qDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayShort(uint256 amount) public onlyModule notPaused {
        quote.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.repay(amount.unwrap(qDec), subAccount1);
    }

    function removeCollateralShort(uint256 amount) public onlyModule notPaused {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0] = IEVC.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(bDec), msg.sender, subAccount1))
        });
        evc.batch(items);
    }

    function addCollateralShort(uint256 amount) public onlyModule notPaused notShutdown {
        base.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.mint(vault0.convertToShares(amount.unwrap(bDec)), subAccount1);
    }

    // ** Helpers

    function syncPositions() external {
        // Intentionally empty as no synchronization is needed for long positions
    }
}
