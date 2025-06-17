// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMerklDistributor {
    /// @notice Claims rewards for a given set of users
    /// @dev Unless another address has been approved for claiming, only an address can claim for itself
    /// @param users Addresses for which claiming is taking place
    /// @param tokens ERC20 token claimed
    /// @param amounts Amount of tokens that will be sent to the corresponding users
    /// @param proofs Array of hashes bridging from a leaf `(hash of user | token | amount)` to the Merkle root
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;

    /// @notice Returns the Merkle root that is currently live for the contract
    function getMerkleRoot() external view returns (bytes32);

    /// @notice Updates the Merkle tree
    function updateTree(MerkleTree calldata _tree) external;

    /// @notice When the current tree becomes valid
    function endOfDisputePeriod() external view returns (uint48);
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
