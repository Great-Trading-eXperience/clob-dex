// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./GTXToken.sol";

contract GTXDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct EpochInfo {
        uint256 tokensToDistribute;
        uint256 startTime;
        uint256 endTime;
        bool distributed;
    }

    struct RewardInfo {
        uint256 amount;
        bool claimed;
    }

    GTXToken public immutable gtxToken;
    
    uint256 public constant EPOCH_DURATION = 7 days;
    uint256 public constant INITIAL_EPOCH_REWARD = 1_000_000 * 10**18; // 1M tokens per epoch initially
    uint256 public constant REWARD_REDUCTION_RATE = 95; // 5% reduction each epoch (95% of previous)
    
    uint256 public currentEpoch;
    uint256 public epochStartTime;
    
    mapping(uint256 => EpochInfo) public epochs;
    mapping(uint256 => mapping(address => RewardInfo)) public userRewards;
    mapping(address => bool) public isRewardDistributor;
    
    event EpochStarted(uint256 indexed epochId, uint256 startTime, uint256 endTime, uint256 tokensToDistribute);
    event RewardDistributed(uint256 indexed epochId, address indexed user, uint256 amount);
    event RewardClaimed(uint256 indexed epochId, address indexed user, uint256 amount);
    event RewardDistributorUpdated(address indexed distributor, bool status);

    constructor(address _gtxToken) Ownable(msg.sender) {
        gtxToken = GTXToken(_gtxToken);
        epochStartTime = block.timestamp;
        _startNewEpoch();
    }

    modifier onlyRewardDistributor() {
        require(isRewardDistributor[msg.sender], "Not authorized");
        _;
    }

    function setRewardDistributor(address distributor, bool status) external onlyOwner {
        isRewardDistributor[distributor] = status;
        emit RewardDistributorUpdated(distributor, status);
    }

    function _startNewEpoch() internal {
        uint256 tokensForEpoch = currentEpoch == 0 
            ? INITIAL_EPOCH_REWARD 
            : (epochs[currentEpoch - 1].tokensToDistribute * REWARD_REDUCTION_RATE) / 100;

        epochs[currentEpoch] = EpochInfo({
            tokensToDistribute: tokensForEpoch,
            startTime: block.timestamp,
            endTime: block.timestamp + EPOCH_DURATION,
            distributed: false
        });

        emit EpochStarted(currentEpoch, block.timestamp, block.timestamp + EPOCH_DURATION, tokensForEpoch);
        currentEpoch++;
    }

    function distributeRewards(uint256 epochId, address[] calldata users, uint256[] calldata amounts) 
        external 
        onlyRewardDistributor 
        nonReentrant 
    {
        require(epochId < currentEpoch, "Invalid epoch");
        require(!epochs[epochId].distributed, "Already distributed");
        require(users.length == amounts.length, "Array length mismatch");
        require(users.length > 0, "Empty arrays");

        EpochInfo storage epoch = epochs[epochId];
        uint256 totalDistribution;

        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid user address");
            require(amounts[i] > 0, "Invalid amount");
            require(!userRewards[epochId][users[i]].claimed, "Already claimed");

            userRewards[epochId][users[i]] = RewardInfo({
                amount: amounts[i],
                claimed: false
            });

            totalDistribution += amounts[i];
            emit RewardDistributed(epochId, users[i], amounts[i]);
        }

        require(totalDistribution <= epoch.tokensToDistribute, "Exceeds epoch allocation");
        epoch.distributed = true;
    }

    function claimRewards(uint256 epochId) external nonReentrant {
        require(epochId < currentEpoch, "Invalid epoch");
        require(epochs[epochId].distributed, "Not yet distributed");
        
        RewardInfo storage reward = userRewards[epochId][msg.sender];
        require(reward.amount > 0, "No rewards");
        require(!reward.claimed, "Already claimed");

        reward.claimed = true;
        gtxToken.mint(msg.sender, reward.amount);

        emit RewardClaimed(epochId, msg.sender, reward.amount);
    }

    function getCurrentEpoch() external view returns (uint256) {
        return currentEpoch;
    }

    function getEpochInfo(uint256 epochId) external view returns (EpochInfo memory) {
        require(epochId < currentEpoch, "Invalid epoch");
        return epochs[epochId];
    }

    function getUserReward(uint256 epochId, address user) external view returns (RewardInfo memory) {
        return userRewards[epochId][user];
    }

    function advanceEpoch() external {
        require(block.timestamp >= epochs[currentEpoch - 1].endTime, "Current epoch not finished");
        _startNewEpoch();
    }
} 