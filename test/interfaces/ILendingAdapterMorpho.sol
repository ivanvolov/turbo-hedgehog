// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {IUniversalRewardsDistributor} from "@universal-rewards-distributor/IUniversalRewardsDistributor.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

interface ILendingAdapterMorpho is ILendingAdapter {
    function claimRewards(address to, IERC20 rewardToken, uint256 claimable, bytes32[] calldata proof) external;

    function setURD(IUniversalRewardsDistributor _URD) external;
}
