// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

// ** External imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMerklDistributor} from "@merkl-contracts/IMerklDistributor.sol";

// ** contracts
import {Base} from "../base/Base.sol";

// ** interfaces
import {ILendingAdapter} from "../../interfaces/ILendingAdapter.sol";

/// @title Lending Base
/// @notice Abstract contract that serves as the base for all lending adapters.
/// @dev Implements the claim rewards functionality using Merkl and updatePosition flow.
abstract contract LendingBase is Base, ILendingAdapter {
    using SafeERC20 for IERC20;

    IMerklDistributor public immutable merklRewardsDistributor;

    constructor(
        IMerklDistributor _merklRewardsDistributor,
        IERC20 _base,
        IERC20 _quote
    ) Base(ComponentType.EXTERNAL_ADAPTER, msg.sender, _base, _quote) {
        merklRewardsDistributor = _merklRewardsDistributor;
    }

    // ** Merkl rewards support

    /// @notice Claims rewards from Merkl.
    /// @param to The address where the tokens will be sent.
    /// @param rewardToken The address of the reward token.
    /// @param claimable The overall claimable amount of token rewards.
    /// @param proof Array of hashes bridging from a leaf to the Merkle root.
    function claimMerklRewards(
        address to,
        IERC20 rewardToken,
        uint256 claimable,
        bytes32[] calldata proof
    ) external notPaused onlyOwner {
        address[] memory users = new address[](1);
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        bytes32[][] memory _proofs = new bytes32[][](1);

        users[0] = address(this);
        tokens[0] = address(rewardToken);
        amounts[0] = claimable;
        _proofs[0] = proof;

        merklRewardsDistributor.claim(users, tokens, amounts, _proofs);
        // The `balanceOf` is necessary because the amount received is not always equal `claimable`.
        // The `to != address(this)` check is necessary to skip transfer for tokens like rEUL, which are locked.
        if (to != address(this)) rewardToken.safeTransfer(to, rewardToken.balanceOf(address(this)));
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
        console.log("!");
        if (deltaCL < 0) addCollateralLong(uint256(-deltaCL));
        if (deltaCS < 0) addCollateralShort(uint256(-deltaCS));

        console.log("!");

        if (deltaDL < 0) repayLong(uint256(-deltaDL));
        if (deltaDS < 0) repayShort(uint256(-deltaDS));

        console.log("!");

        if (deltaCL > 0) removeCollateralLong(uint256(deltaCL));
        if (deltaCS > 0) removeCollateralShort(uint256(deltaCS));

        console.log("!");

        if (deltaDL > 0) borrowLong(uint256(deltaDL));
        if (deltaDS > 0) borrowShort(uint256(deltaDS));

        console.log("!");
    }

    // ** Long and short markets unimplemented functions

    function addCollateralLong(uint256 amount) public virtual;

    function addCollateralShort(uint256 amount) public virtual;

    function repayLong(uint256 amount) public virtual;

    function repayShort(uint256 amount) public virtual;

    function removeCollateralLong(uint256 amount) public virtual;

    function removeCollateralShort(uint256 amount) public virtual;

    function borrowLong(uint256 amount) public virtual;

    function borrowShort(uint256 amount) public virtual;

    function getCollateralLong() public view virtual returns (uint256);

    function getCollateralShort() public view virtual returns (uint256);

    function getBorrowedLong() public view virtual returns (uint256);

    function getBorrowedShort() public view virtual returns (uint256);
}
