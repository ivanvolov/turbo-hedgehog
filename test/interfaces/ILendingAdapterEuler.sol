// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";

interface ILendingAdapterEuler is ILendingAdapter {
    function claimMerklRewards(address to, IERC20 rewardToken, uint256 claimable, bytes32[] calldata proof) external;

    function unlockRewardEUL(address to, uint256 lockTimestamp) external;
}
