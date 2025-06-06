pragma solidity ^0.8.0;

import "../incentives/libraries/VeBalanceLib.sol";
import "../incentives/libraries/VeHistoryLib.sol";

interface IVotingController {
    event AddPool(uint64 indexed chainId, address indexed pool);

    event RemovePool(uint64 indexed chainId, address indexed pool);

    event Vote(address indexed user, address indexed pool, uint64 weight, VeBalance vote);

    event PoolVoteChange(address indexed pool, VeBalance vote);

    event SetTokenPerSec(uint256 newTokenPerSec);

    event BroadcastResults(uint64 indexed chainId, uint128 indexed wTime, uint128 totalTokenPerSec);

    function applyPoolSlopeChanges(
        address pool
    ) external;

    /// @notice deprecated, only kept for compatibility reasons
    function getUserPoolHistoryLength(address user, address pool) external view returns (uint256);

    /// @notice deprecated, only kept for compatibility reasons
    function getUserPoolHistoryAt(
        address user,
        address pool,
        uint256 index
    ) external view returns (Checkpoint memory);

    function getWeekData(
        uint128 wTime,
        address[] calldata pools
    )
        external
        view
        returns (bool isEpochFinalized, uint128 totalVotes, uint128[] memory poolVotes);

    function getPoolTotalVoteAt(address pool, uint128 wTime) external view returns (uint128);

    function finalizeEpoch() external;

    function getBroadcastResultFee(
        uint64 chainId
    ) external view returns (uint256);

    function broadcastResults(
        uint64 chainId
    ) external payable;
}
