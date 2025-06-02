// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Euler imports
import {IEVault as IEulerVault} from "@euler-interfaces/IEulerVault.sol";
import {IEVC as EVCLib, IEthereumVaultConnector as IEVC} from "@euler-interfaces/IEVC.sol";
import {IRewardToken as IrEUL} from "@euler-interfaces/IRewardToken.sol";

// ** External imports
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ** libraries
import {TokenWrapperLib} from "../../libraries/TokenWrapperLib.sol";

// ** contracts
import {LendingBase} from "../lendingAdapters/LendingBase.sol";

contract EulerLendingAdapter is LendingBase {
    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** EulerV2
    IEVC immutable evc;
    IEulerVault public immutable vault0;
    IEulerVault public immutable vault1;
    IrEUL public immutable rEUL;
    address public immutable subAccount0 = getSubAccountAddress(1);
    address public immutable subAccount1 = getSubAccountAddress(2);

    constructor(
        IERC20 _base,
        IERC20 _quote,
        uint8 _bDec,
        uint8 _qDec,
        IEVC _evc,
        IEulerVault _vault0,
        IEulerVault _vault1,
        IMerklDistributor _merklRewardsDistributor,
        IrEUL _rEUL
    ) LendingBase(_merklRewardsDistributor, _base, _quote, _bDec, _qDec) {
        evc = _evc;
        vault0 = _vault0;
        vault1 = _vault1;
        rEUL = _rEUL;

        evc.enableController(subAccount0, address(vault0));
        evc.enableCollateral(subAccount0, address(vault1));
        evc.enableController(subAccount1, address(vault1));
        evc.enableCollateral(subAccount1, address(vault0));

        BASE.forceApprove(address(vault0), type(uint256).max);
        QUOTE.forceApprove(address(vault0), type(uint256).max);
        BASE.forceApprove(address(vault1), type(uint256).max);
        QUOTE.forceApprove(address(vault1), type(uint256).max);
    }

    function getSubAccountAddress(uint8 accountId) internal view returns (address) {
        return address(uint160(address(this)) ^ uint160(accountId));
    }

    // ** rEUL unlocking support

    function unlockRewardEUL(address to, uint256 lockTimestamp) external notPaused onlyOwner {
        rEUL.withdrawToByLockTimestamp(to, lockTimestamp, true);
    }

    // ** Long market

    function getBorrowedLong() public view override returns (uint256) {
        return vault0.debtOf(subAccount0).wrap(bDec);
    }

    function getCollateralLong() public view override returns (uint256) {
        return vault1.convertToAssets(vault1.balanceOf(subAccount0)).wrap(qDec);
    }

    function borrowLong(uint256 amount) public override onlyModule onlyActive {
        EVCLib.BatchItem[] memory items = new EVCLib.BatchItem[](1);

        items[0] = EVCLib.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(bDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayLong(uint256 amount) public override onlyModule notPaused {
        BASE.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.repay(amount.unwrap(bDec), subAccount0);
    }

    function removeCollateralLong(uint256 amount) public override onlyModule notPaused {
        EVCLib.BatchItem[] memory items = new EVCLib.BatchItem[](1);
        items[0] = EVCLib.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount0,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(qDec), msg.sender, subAccount0))
        });
        evc.batch(items);
    }

    function addCollateralLong(uint256 amount) public override onlyModule onlyActive {
        QUOTE.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.mint(vault1.convertToShares(amount.unwrap(qDec)), subAccount0);
    }

    // ** Short market

    function getBorrowedShort() public view override returns (uint256) {
        return vault1.debtOf(subAccount1).wrap(qDec);
    }

    function getCollateralShort() public view override returns (uint256) {
        return vault0.convertToAssets(vault0.balanceOf(subAccount1)).wrap(bDec);
    }

    function borrowShort(uint256 amount) public override onlyModule onlyActive {
        EVCLib.BatchItem[] memory items = new EVCLib.BatchItem[](1);

        items[0] = EVCLib.BatchItem({
            targetContract: address(vault1),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.borrow, (amount.unwrap(qDec), msg.sender))
        });
        evc.batch(items);
    }

    function repayShort(uint256 amount) public override onlyModule notPaused {
        QUOTE.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        vault1.repay(amount.unwrap(qDec), subAccount1);
    }

    function removeCollateralShort(uint256 amount) public override onlyModule notPaused {
        EVCLib.BatchItem[] memory items = new EVCLib.BatchItem[](1);
        items[0] = EVCLib.BatchItem({
            targetContract: address(vault0),
            onBehalfOfAccount: subAccount1,
            value: 0,
            data: abi.encodeCall(IEulerVault.withdraw, (amount.unwrap(bDec), msg.sender, subAccount1))
        });
        evc.batch(items);
    }

    function addCollateralShort(uint256 amount) public override onlyModule onlyActive {
        BASE.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        vault0.mint(vault0.convertToShares(amount.unwrap(bDec)), subAccount1);
    }

    // ** Helpers

    function syncPositions() external {
        // Intentionally empty as no synchronization is needed for long positions
    }
}
