// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// ** External imports
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ** interfaces
import {ILendingAdapter} from "@src/interfaces/ILendingAdapter.sol";
import {IUniversalRewardsDistributor} from "@src/interfaces/lendingAdapters/IUniversalRewardsDistributor.sol";

interface ILendingAdapterMorpho is ILendingAdapter {
    function claimRewards(address to, IERC20 rewardToken, uint256 claimable, bytes32[] calldata proof) external;

    function setURD(IUniversalRewardsDistributor _URD) external;
}

struct PendingRoot {
    /// @dev The submitted pending root.
    bytes32 root;
    /// @dev The optional ipfs hash containing metadata about the root (e.g. the merkle tree itself).
    bytes32 ipfsHash;
    /// @dev The timestamp at which the pending root can be accepted.
    uint256 validAt;
}

interface IUniversalRewardsDistributorFull {
    function claimed(address, address) external view returns (uint256);

    function root() external view returns (bytes32);

    function acceptRoot() external;

    function submitRoot(bytes32 newRoot, bytes32 ipfsHash) external;

    function claim(
        address account,
        address reward,
        uint256 claimable,
        bytes32[] memory proof
    ) external returns (uint256 amount);

    function pendingRoot() external view returns (PendingRoot memory);
}
