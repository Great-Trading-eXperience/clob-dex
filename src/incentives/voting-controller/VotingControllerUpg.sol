// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./VotingControllerStorageUpg.sol";
import "../crosschain/MsgSenderAppUpd.sol";
import "../libraries/VeBalanceLib.sol";
import "../libraries/PMath.sol";
import "../../interfaces/IGaugeControllerMainchain.sol";
import "../../interfaces/IVotingController.sol";
// import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/*
Voting accounting:
    - For gauge controller, it will consider each message from voting controller
    as a pack of money to incentivize it during the very next WEEK (block.timestamp -> block.timestamp + WEEK)
    - If the reward duration for the last pack of money has not ended, it will combine
    the leftover reward with the current reward to distribute.

    - In the very extreme case where no one broadcast the result of week x, and at week x+1,
    the results for both are now broadcasted, then the WEEK of (block.timestamp -> WEEK)
    will receive both of the reward pack
    - Each pack of money will has it own id as timestamp, a gauge controller does not
    receive a pack of money with the same id twice, this allow governance to rebroadcast
    in case the last message was corrupted by LayerZero

Pros:
    - If governance does not forget broadcasting the reward on the early of the week,
    the mechanism works just the same as the epoch-based one
    - If governance forget to broadcast the reward, the whole system still works normally,
    the reward is still incentivized, but only approximately fair
Cons:
    - Does not guarantee the reward will be distributed on epoch start and end
*/

contract VotingControllerUpg is Initializable, VotingControllerStorageUpg, MsgSenderAppUpd {
    using VeBalanceLib for VeBalance;
    using PMath for uint256;
    using PMath for int256;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    error ArrayLengthMismatch();
    error VCZeroVeToken(address user);
    error VCExceededMaxWeight(uint256 totalVotedWeight, uint256 maxWeight);
    error VCEpochNotFinalized(uint128 wTime);
    error VCPoolAlreadyActive(address pool);
    error VCPoolAlreadyAddAndRemoved(address pool);

    constructor(
        address _veToken,
        address _tokenMsgSendEndpoint
    ) VotingControllerStorageUpg(_veToken) MsgSenderAppUpd(_tokenMsgSendEndpoint) {
        _disableInitializers();
    }

    function initialize(
        uint256 _initialApproxDestinationGas
    ) external initializer {
        deployedWTime = WeekMath.getCurrentWeekStart();
        __MsgSenderAppUpd_init(_initialApproxDestinationGas);
        __Ownable_init(msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                FUNCTIONS CAN BE CALLED BY ANYONE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice updates a user's vote weights, also allowing user to divide their voting power
     * across different pools
     * @param pools pools to change vote weights, if not listed then existing weight won't change
     * @param weights voting weight on each pool in `pools`, must be same length as `pools`
     * @dev A user's max voting weights is equal to `USER_VOTE_MAX_WEIGHT` (1e18). If their total
     * voted weights is less than such, then the excess weight is not counted. For such reason, a
     * user's voting power will only be fully utilized if their total voted weight is exactly 1e18.
     * @dev Reverts if, after all vote changes, the total voted weight is more than 1e18.
     * @dev A removed pool can be included, but the new weight must be 0, otherwise will revert.
     * @dev See {`VotingControllerStorageUpg - getUserData()`} for current user data.
     */
    function vote(address[] calldata pools, uint64[] calldata weights) external {
        address user = msg.sender;

        if (pools.length != weights.length) revert ArrayLengthMismatch();
        if (user != owner() && veToken.balanceOf(user) == 0) revert VCZeroVeToken(user);

        LockedPosition memory userPosition = _getUserVeTokenPosition(user);

        for (uint256 i = 0; i < pools.length; ++i) {
            if (_isPoolActive(pools[i])) applyPoolSlopeChanges(pools[i]);
            VeBalance memory newVote = _modifyVoteWeight(user, pools[i], userPosition, weights[i]);
            emit Vote(user, pools[i], weights[i], newVote);
        }

        uint256 totalVotedWeight = userData[user].totalVotedWeight;
        if (totalVotedWeight > VeBalanceLib.USER_VOTE_MAX_WEIGHT) {
            revert VCExceededMaxWeight(totalVotedWeight, VeBalanceLib.USER_VOTE_MAX_WEIGHT);
        }
    }

    /**
     * @notice Process all the slopeChanges that haven't been processed & update these data into
     * poolData
     * @dev reverts if pool is not active
     * @dev if pool is already up-to-date, the function will succeed without any state updates
     */
    function applyPoolSlopeChanges(
        address pool
    ) public {
        if (!_isPoolActive(pool)) revert VCInactivePool(pool);

        uint128 wTime = poolData[pool].lastSlopeChangeAppliedAt;
        uint128 currentWeekStart = WeekMath.getCurrentWeekStart();

        // no state changes are expected
        if (wTime >= currentWeekStart) return;

        VeBalance memory currentVote = poolData[pool].totalVote;
        while (wTime < currentWeekStart) {
            wTime += WEEK;
            currentVote = currentVote.sub(poolData[pool].slopeChanges[wTime], wTime);
            _setFinalPoolVoteForWeek(pool, wTime, currentVote.getValueAt(wTime));
        }

        _setNewVotePoolData(pool, currentVote, wTime);
    }

    /**
     * @notice finalize the voting results of all pools, up to the current epoch
     * @dev See `applyPoolSlopeChanges()` for more details
     * @dev This function might be gas-costly if there are a lot of active pools, but this can be
     * mitigated by calling `applyPoolSlopeChanges()` for each pool separately, spreading the gas
     * cost across multiple txs (although the total gas cost will be higher).
     * This is because `applyPoolSlopeChanges()` will not update anything if already up-to-date.
     */
    function finalizeEpoch() public {
        uint256 length = allActivePools.length();
        for (uint256 i = 0; i < length; ++i) {
            applyPoolSlopeChanges(allActivePools.at(i));
        }
        _setAllPastEpochsAsFinalized();
    }

    /**
     * @notice broadcast the voting results of the current week to the chain with chainId. Can be
     * called by anyone.
     * @dev It's intentional to allow the same results to be broadcasted multiple
     * times. The receiver should be able to filter these duplicated messages
     * @dev The epoch must have already been finalized by `finalizeEpoch()`, otherwise will revert.
     */
    function broadcastResults(
        uint64 chainId
    ) external payable refundUnusedEth {
        uint128 wTime = WeekMath.getCurrentWeekStart();
        if (!weekData[wTime].isEpochFinalized) revert VCEpochNotFinalized(wTime);
        _broadcastResults(chainId, wTime, tokenPerSec);
    }

    /*///////////////////////////////////////////////////////////////
                    GOVERNANCE-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAddPoolHelperAndOwner() {
        require(msg.sender == addPoolHelper || msg.sender == owner(), "add pool not allowed");
        _;
    }

    modifier onlyRemovePoolHelperAndOwner() {
        require(msg.sender == removePoolHelper || msg.sender == owner(), "remove pool not allowed");
        _;
    }

    /**
     * @notice add a pool to allow users to vote. Can only be done by [governance/owner helper]
     * @custom:gov NOTE TO GOV:
     * - Previous week's results should have been broadcasted prior to calling this function.
     * - `pool` must not have been added before (even if has been removed).
     * - `chainId` must be valid.
     */
    function addPool(uint64 chainId, address pool) external onlyAddPoolHelperAndOwner {
        if (_isPoolActive(pool)) revert VCPoolAlreadyActive(pool);
        if (allRemovedPools.contains(pool)) revert VCPoolAlreadyAddAndRemoved(pool);

        _addPool(chainId, pool);
        emit AddPool(chainId, pool);
    }

    function addMultiPools(
        uint64[] memory chainIds,
        address[] memory pools
    ) external onlyAddPoolHelperAndOwner {
        if (chainIds.length != pools.length) revert ArrayLengthMismatch();
        for (uint256 i = 0; i < chainIds.length; ++i) {
            (uint64 chainId, address pool) = (chainIds[i], pools[i]);
            if (_isPoolActive(pool)) revert VCPoolAlreadyActive(pool);
            if (allRemovedPools.contains(pool)) revert VCPoolAlreadyAddAndRemoved(pool);

            _addPool(chainId, pool);
            emit AddPool(chainId, pool);
        }
    }

    /**
     * @notice remove a pool from voting. Can only be done by governance
     * @custom:gov NOTE TO GOV:
     * - Previous week's results should have been broadcasted prior to calling this function.
     * - `pool` must be currently active.
     */
    function removePool(
        address pool
    ) external onlyRemovePoolHelperAndOwner {
        if (!_isPoolActive(pool)) revert VCInactivePool(pool);

        uint64 chainId = poolData[pool].chainId;

        applyPoolSlopeChanges(pool);
        _removePool(pool);

        emit RemovePool(chainId, pool);
    }

    /**
     * @notice use the gov-privilege to force broadcast a message in case there are issues with LayerZero
     * @custom:gov NOTE TO GOV: gov should always call finalizeEpoch beforehand
     */
    function forceBroadcastResults(
        uint64 chainId,
        uint128 wTime,
        uint128 forcedTokenPerSec
    ) external payable onlyOwner refundUnusedEth {
        _broadcastResults(chainId, wTime, forcedTokenPerSec);
    }

    /**
     * @notice sets new tokenPerSec
     * @dev no zero checks because gov may want to stop liquidity mining
     * @custom:gov NOTE TO GOV: Should be done mid-week, well before the next broadcast to avoid
     * race condition
     */
    function setTokenPerSec(
        uint128 newTokenPerSec
    ) external onlyOwner {
        tokenPerSec = newTokenPerSec;
        emit SetTokenPerSec(newTokenPerSec);
    }

    function getBroadcastResultFee(
        uint64 chainId
    ) external view returns (uint256) {
        if (chainId == block.chainid) return 0; // Mainchain broadcast

        uint256 length = activeChainPools[chainId].length();
        if (length == 0) return 0;

        address[] memory pools = new address[](length);
        uint256[] memory totalTokenAmounts = new uint256[](length);

        return _getSendMessageFee(chainId, abi.encode(uint128(0), pools, totalTokenAmounts));
    }

    /*///////////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice broadcast voting results of the timestamp to chainId
    function _broadcastResults(uint64 chainId, uint128 wTime, uint128 totalTokenPerSec) internal {
        uint256 totalVotes = weekData[wTime].totalVotes;
        if (totalVotes == 0) return;

        uint256 length = activeChainPools[chainId].length();
        if (length == 0) return;

        address[] memory pools = activeChainPools[chainId].values();
        uint256[] memory totalTokenAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            uint256 poolVotes = weekData[wTime].poolVotes[pools[i]];
            totalTokenAmounts[i] = (totalTokenPerSec * poolVotes * WEEK) / totalVotes;
        }

        if (chainId == block.chainid) {
            address gaugeController = _getMsgSenderStorage().destinationContracts.get(chainId);
            IGaugeControllerMainchain(gaugeController).updateVotingResults(
                wTime, pools, totalTokenAmounts
            );
        } else {
            _sendMessage(chainId, abi.encode(wTime, pools, totalTokenAmounts));
        }

        emit BroadcastResults(chainId, wTime, totalTokenPerSec);
    }

    function _getUserVeTokenPosition(
        address user
    ) internal view returns (LockedPosition memory userPosition) {
        if (user == owner()) {
            (userPosition.amount, userPosition.expiry) = (
                GOVERNANCE_VOTE,
                WeekMath.getWeekStartTimestamp(uint128(block.timestamp) + MAX_LOCK_TIME)
            );
        } else {
            (userPosition.amount, userPosition.expiry) = veToken.positionData(user);
        }
    }

    function setAddPoolHelper(
        address _helper
    ) public onlyOwner {
        addPoolHelper = _helper;
    }

    function setRemovePoolHelper(
        address _helper
    ) public onlyOwner {
        removePoolHelper = _helper;
    }
}
