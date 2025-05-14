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

struct MerkleTree {
    // Root of a Merkle tree which leaves are `(address user, address token, uint amount)`
    // representing an amount of tokens accumulated by `user`.
    // The Merkle tree is assumed to have only increasing amounts: that is to say if a user can claim 1,
    // then after the amount associated in the Merkle tree for this token should be x > 1
    bytes32 merkleRoot;
    // Ipfs hash of the tree data
    bytes32 ipfsHash;
}

interface IMerklDistributorFull {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;

    function getMerkleRoot() external view returns (bytes32);

    function updateTree(MerkleTree calldata _tree) external;

    function endOfDisputePeriod() external view returns (uint48);
}

interface IrEULFull is IERC20 {
    function getLockedAmountsLength(address account) external view returns (uint256);

    function getLockedAmountsLockTimestamps(address account) external view returns (uint256[] memory);

    function getLockedAmounts(
        address account
    ) external view returns (uint256[] memory lockTimestamps, uint256[] memory amounts);

    function withdrawToByLockTimestamp(
        address account,
        uint256 lockTimestamp,
        bool allowRemainderLoss
    ) external returns (bool);
}
