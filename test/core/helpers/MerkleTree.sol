// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MerkleTree
 * @dev Simple Merkle tree implementation for testing
 * Used to generate roots and proofs for yield claim testing
 */
contract MerkleTree {
    /**
     * @dev Get Merkle root from leaves
     * Simple implementation: hashes pairs until single root
     */
    function getRoot(bytes32[] memory leaves) public pure returns (bytes32) {
        if (leaves.length == 0) return bytes32(0);
        if (leaves.length == 1) return leaves[0];

        // Sort leaves for deterministic tree
        _sort(leaves);

        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    nextLevel[i / 2] = _hashPair(currentLevel[i], currentLevel[i + 1]);
                } else {
                    // Odd number of nodes - promote last one
                    nextLevel[i / 2] = currentLevel[i];
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    /**
     * @dev Get Merkle proof for a leaf at given index (before sorting)
     * IMPORTANT: Index refers to position BEFORE sorting
     */
    function getProof(bytes32[] memory leaves, uint256 index) public pure returns (bytes32[] memory) {
        require(index < leaves.length, "Index out of bounds");

        // Store the target leaf value before sorting
        bytes32 targetLeaf = leaves[index];

        // Sort leaves
        _sort(leaves);

        // Find the new index of targetLeaf after sorting
        uint256 sortedIndex = 0;
        for (uint256 i = 0; i < leaves.length; i++) {
            if (leaves[i] == targetLeaf) {
                sortedIndex = i;
                break;
            }
        }

        // Calculate proof length (tree height)
        uint256 proofLength = 0;
        uint256 n = leaves.length;
        while (n > 1) {
            proofLength++;
            n = (n + 1) / 2;
        }

        bytes32[] memory proof = new bytes32[](proofLength);
        uint256 proofIndex = 0;
        uint256 currentIndex = sortedIndex; // Use sorted index, not original
        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            bytes32[] memory nextLevel = new bytes32[]((currentLevel.length + 1) / 2);

            for (uint256 i = 0; i < currentLevel.length; i += 2) {
                if (i + 1 < currentLevel.length) {
                    nextLevel[i / 2] = _hashPair(currentLevel[i], currentLevel[i + 1]);

                    // Add sibling to proof if current node is being proven
                    if (i == currentIndex) {
                        proof[proofIndex++] = currentLevel[i + 1];
                        currentIndex = i / 2;
                    } else if (i + 1 == currentIndex) {
                        proof[proofIndex++] = currentLevel[i];
                        currentIndex = i / 2;
                    }
                } else {
                    // Odd number - promote last node
                    nextLevel[i / 2] = currentLevel[i];
                    if (i == currentIndex) {
                        currentIndex = i / 2;
                    }
                }
            }

            currentLevel = nextLevel;
        }

        // Trim proof if needed
        bytes32[] memory trimmedProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            trimmedProof[i] = proof[i];
        }

        return trimmedProof;
    }

    /**
     * @dev Hash a pair of nodes (sorted to ensure deterministic tree)
     */
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @dev Simple bubble sort for bytes32 array
     */
    function _sort(bytes32[] memory arr) internal pure {
        uint256 n = arr.length;
        for (uint256 i = 0; i < n - 1; i++) {
            for (uint256 j = 0; j < n - i - 1; j++) {
                if (arr[j] > arr[j + 1]) {
                    bytes32 temp = arr[j];
                    arr[j] = arr[j + 1];
                    arr[j + 1] = temp;
                }
            }
        }
    }
}
