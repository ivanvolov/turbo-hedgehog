// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** Morpho imports
import {IMorpho, Id, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";
import {IUniversalRewardsDistributor} from "@universal-rewards-distributor/IUniversalRewardsDistributor.sol";

// ** libraries
import {TokenWrapperLib} from "../../libraries/TokenWrapperLib.sol";

// ** contracts
import {LendingBase} from "../lendingAdapters/LendingBase.sol";

/// @title Morpho Lending Adapter
/// @notice Implementation of the lending adapter using Morpho.
contract MorphoLendingAdapter is LendingBase {
    error NotInBorrowMode();

    using TokenWrapperLib for uint256;
    using SafeERC20 for IERC20;

    // ** Morpho
    IMorpho immutable morpho;
    IUniversalRewardsDistributor public URD;
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
        IERC4626 _earnQuote,
        IMerklDistributor _merklRewardsDistributor
    ) LendingBase(_merklRewardsDistributor, _base, _quote, _bDec, _qDec) {
        morpho = _morpho;

        BASE.forceApprove(address(morpho), type(uint256).max);
        QUOTE.forceApprove(address(morpho), type(uint256).max);
        if (address(_earnQuote) != address(0) && address(_earnBase) != address(0)) {
            isEarn = true;
            earnQuote = _earnQuote;
            earnBase = _earnBase;
            BASE.forceApprove(address(earnBase), type(uint256).max);
            QUOTE.forceApprove(address(earnQuote), type(uint256).max);
        } else {
            isEarn = false;
            longMId = _longMId;
            shortMId = _shortMId;
        }
    }

    // ** Morpho rewards support

    function setURD(IUniversalRewardsDistributor _URD) external onlyOwner {
        URD = _URD;
    }

    /// @notice Claims rewards from Universal Rewards Distributor.
    /// @param to The address where the tokens will be sent.
    /// @param rewardToken The address of the reward token.
    /// @param claimable The overall claimable amount of token rewards.
    /// @param proof The merkle proof that validates this claim.
    function claimRewards(
        address to,
        IERC20 rewardToken,
        uint256 claimable,
        bytes32[] calldata proof
    ) external notPaused onlyOwner {
        URD.claim(address(this), address(rewardToken), claimable, proof);
        // The `balanceOf` is necessary because the amount received is not always equal `claimable`.
        // This happens in case some rewards were already claimed.
        rewardToken.safeTransfer(to, rewardToken.balanceOf(address(this)));
    }

    // ** Long market

    function getBorrowedLong() public view override returns (uint256) {
        if (isEarn) return 0;
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(longMId), address(this)).wrap(bDec);
    }

    function getCollateralLong() public view override returns (uint256) {
        if (isEarn) return earnQuote.convertToAssets(earnQuote.balanceOf(address(this))).wrap(qDec);
        Position memory p = morpho.position(longMId, address(this));
        return uint256(p.collateral).wrap(qDec);
    }

    function borrowLong(uint256 amount) public override onlyModule onlyActive isBorrowMode {
        morpho.borrow(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), msg.sender);
    }

    function repayLong(uint256 amount) public override onlyModule notPaused isBorrowMode {
        BASE.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        morpho.repay(morpho.idToMarketParams(longMId), amount.unwrap(bDec), 0, address(this), "");
    }

    function removeCollateralLong(uint256 amount) public override onlyModule notPaused {
        if (isEarn) earnQuote.withdraw(amount.unwrap(qDec), msg.sender, address(this));
        else
            morpho.withdrawCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), msg.sender);
    }

    function addCollateralLong(uint256 amount) public override onlyModule onlyActive {
        QUOTE.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        if (isEarn) earnQuote.deposit(amount.unwrap(qDec), address(this));
        else morpho.supplyCollateral(morpho.idToMarketParams(longMId), amount.unwrap(qDec), address(this), "");
    }

    // ** Short market

    function getBorrowedShort() public view override returns (uint256) {
        if (isEarn) return 0;
        return
            MorphoBalancesLib.expectedBorrowAssets(morpho, morpho.idToMarketParams(shortMId), address(this)).wrap(qDec);
    }

    function getCollateralShort() public view override returns (uint256) {
        if (isEarn) return earnBase.convertToAssets(earnBase.balanceOf(address(this))).wrap(bDec);
        Position memory p = morpho.position(shortMId, address(this));
        return uint256(p.collateral).wrap(bDec);
    }

    function borrowShort(uint256 amount) public override onlyModule onlyActive isBorrowMode {
        morpho.borrow(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), msg.sender);
    }

    function repayShort(uint256 amount) public override onlyModule notPaused isBorrowMode {
        QUOTE.safeTransferFrom(msg.sender, address(this), amount.unwrap(qDec));
        morpho.repay(morpho.idToMarketParams(shortMId), amount.unwrap(qDec), 0, address(this), "");
    }

    function removeCollateralShort(uint256 amount) public override onlyModule notPaused {
        if (isEarn) earnBase.withdraw(amount.unwrap(bDec), msg.sender, address(this));
        else
            morpho.withdrawCollateral(
                morpho.idToMarketParams(shortMId),
                amount.unwrap(bDec),
                address(this),
                msg.sender
            );
    }

    function addCollateralShort(uint256 amount) public override onlyModule onlyActive {
        BASE.safeTransferFrom(msg.sender, address(this), amount.unwrap(bDec));
        if (isEarn) earnBase.deposit(amount.unwrap(bDec), address(this));
        else morpho.supplyCollateral(morpho.idToMarketParams(shortMId), amount.unwrap(bDec), address(this), "");
    }

    // ** Helpers

    function syncPositions() external {
        if (!isEarn) {
            morpho.accrueInterest(morpho.idToMarketParams(longMId));
            morpho.accrueInterest(morpho.idToMarketParams(shortMId));
        }
    }

    // ** Modifiers

    modifier isBorrowMode() {
        if (isEarn) revert NotInBorrowMode();
        _;
    }
}
