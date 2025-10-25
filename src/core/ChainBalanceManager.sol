// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IChainBalanceManager} from "./interfaces/IChainBalanceManager.sol";
import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {Currency} from "./libraries/Currency.sol";
import {HyperlaneMessages} from "./libraries/HyperlaneMessages.sol";
import {ChainBalanceManagerStorage} from "./storages/ChainBalanceManagerStorage.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title ChainBalanceManager
 * @dev Upgradeable vault contract for source chains with Espresso Hyperlane integration
 * Follows proven patterns from the working Espresso testnet implementation
 */
contract ChainBalanceManager is
    IChainBalanceManager,
    IMessageRecipient,
    ChainBalanceManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using HyperlaneMessages for *;
    using SafeERC20 for IERC20;

    // Additional events not in interface
    event BridgeToSynthetic(
        address indexed user, address indexed sourceToken, address indexed syntheticToken, uint256 amount
    );
    event WithdrawMessageReceived(address indexed user, address indexed token, uint256 amount);
    event TokenMappingSet(address indexed sourceToken, address indexed syntheticToken);
    event NonceIncremented(address indexed user, uint256 newNonce);
    event CrossChainConfigUpdated(uint32 indexed destinationDomain, address indexed destinationBalanceManager);
    event DestinationChainConfigUpdated(bool isDestinationChain, address messageHandler);
    event LocalDomainUpdated(uint32 indexed oldDomain, uint32 indexed newDomain);

    // Yield system events
    event VaultSet(address indexed token, address indexed vault);
    event VaultRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event VaultDeposit(address indexed token, address indexed vault, uint256 amount, uint256 shares);
    event TokenSnapshotUpdated(uint256 indexed day, address indexed token, bytes32 merkleRoot, uint256 totalSupply);
    event DailySnapshotUpdated(uint256 indexed day, uint256 tokenCount);
    event YieldClaimed(address indexed user, address indexed token, uint256 amount, uint256 day);

    // Constants
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant DEFAULT_VAULT_RATIO = 8000; // 80%

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize ChainBalanceManager for cross-chain operation only
     * @param _owner Contract owner
     * @param _mailbox Hyperlane mailbox for cross-chain messaging
     * @param _destinationDomain Target chain domain (Rari: 1918988905)
     * @param _destinationBalanceManager BalanceManager address on Rari
     */
    function initialize(
        address _owner,
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        
        // Use chain ID as domain (Hyperlane convention)
        $.localDomain = uint32(block.chainid);
        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;
        $.isDestinationChain = false; // Always cross-chain mode
        $.messageHandler = _mailbox;
        $.mailbox = _mailbox;
        
        // Validate we're targeting a different chain (source -> destination)
        if ($.localDomain == _destinationDomain) {
            revert("ChainBalanceManager requires different source and destination chains");
        }
        
        emit DestinationChainConfigUpdated(false, _mailbox);
        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }

    /**
     * @dev Legacy compatibility function - use main initialize instead
     */
    function initializeCrossChain(
        address _owner,
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) public initializer {
        initialize(_owner, _mailbox, _destinationDomain, _destinationBalanceManager);
    }

    // Legacy interface compatibility - use overloading
    function initialize(
        address _owner
    ) external override {
        revert("Use initialize with full parameters");
    }

    modifier onlyWhitelistedToken(
        address token
    ) {
        Storage storage $ = getStorage();
        if (!$.whitelistedTokens[token] && token != address(0)) {
            revert TokenNotWhitelisted(token);
        }
        _;
    }

    modifier onlyMailbox() {
        Storage storage $ = getStorage();
        // For backward compatibility, check both mailbox and messageHandler
        if (msg.sender != $.mailbox && msg.sender != $.messageHandler) {
            revert OnlyMailbox();
        }
        _;
    }

    // =============================================================
    //                     CORE VAULT FUNCTIONS
    // =============================================================

    function deposit(
        address token,
        uint256 amount,
        address recipient
    ) external payable nonReentrant onlyWhitelistedToken(token) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (recipient == address(0)) {
            revert ZeroAddress();
        }

        Storage storage $ = getStorage();
        
        // Transfer tokens to this contract
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount sent");
        } else {
            require(msg.value == 0, "No ETH should be sent for ERC20 deposit");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        $.totalDeposited[token] += amount;

        // Deploy to vault if configured (only for ERC20 tokens)
        if (token != address(0)) {
            address vault = $.vaults[token];
            if (vault != address(0)) {
                // Use configured ratio or default (80%)
                uint256 ratio = $.vaultRatio > 0 ? $.vaultRatio : DEFAULT_VAULT_RATIO;
                uint256 vaultAmount = (amount * ratio) / BASIS_POINTS;

                if (vaultAmount > 0) {
                    // Approve vault to spend tokens
                    IERC20(token).approve(vault, vaultAmount);

                    // Deposit to ERC-4626 vault and track shares received
                    uint256 shares = IERC4626(vault).deposit(vaultAmount, address(this));
                    $.vaultShares[token] += shares;

                    emit VaultDeposit(token, vault, vaultAmount, shares);
                }
            }
        }

        // Get and increment user nonce (security pattern)
        uint256 currentNonce = $.userNonces[recipient]++;
        emit NonceIncremented(recipient, $.userNonces[recipient]);

        // Get synthetic token mapping
        address syntheticToken = $.sourceToSynthetic[token];
        if (syntheticToken == address(0)) {
            revert TokenMappingNotFound(token);
        }

        // Always cross-chain - send Hyperlane message to Rari
        _handleCrossChainDeposit(token, syntheticToken, amount, recipient, currentNonce);

        emit Deposit(msg.sender, recipient, token, amount);
        emit BridgeToSynthetic(recipient, token, syntheticToken, amount);
    }


    /**
     * @dev Handle cross-chain deposit - send Hyperlane message to Rari
     */
    function _handleCrossChainDeposit(
        address token,
        address syntheticToken,
        uint256 amount,
        address recipient,
        uint256 nonce
    ) internal {
        Storage storage $ = getStorage();

        // Create message for BalanceManager on Rari
        HyperlaneMessages.DepositMessage memory message = HyperlaneMessages.DepositMessage({
            messageType: HyperlaneMessages.DEPOSIT_MESSAGE,
            syntheticToken: syntheticToken,
            user: recipient, // Mint to recipient
            amount: amount,
            sourceChainId: $.localDomain,
            nonce: nonce
        });

        // Send cross-chain message via Hyperlane to Rari BalanceManager
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160($.destinationBalanceManager)));

        IMailbox($.mailbox).dispatch($.destinationDomain, recipientAddress, messageBody);
    }


    /**
     * @dev Handle cross-chain messages from Rari (Espresso pattern)
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _messageBody
    ) external payable override onlyMailbox nonReentrant {
        Storage storage $ = getStorage();

        // Verify origin and sender (Espresso security pattern)
        if (_origin != $.destinationDomain) {
            revert InvalidOrigin(_origin);
        }

        if (_sender != bytes32(uint256(uint160($.destinationBalanceManager)))) {
            revert InvalidSender(_sender);
        }

        // Generate message ID for replay protection
        bytes32 messageId = HyperlaneMessages.generateMessageId(_origin, _sender, _messageBody);
        if ($.processedMessages[messageId]) {
            revert MessageAlreadyProcessed(messageId);
        }
        $.processedMessages[messageId] = true;

        // Process message based on type
        uint8 messageType = HyperlaneMessages.decodeMessageType(_messageBody);

        if (messageType == HyperlaneMessages.WITHDRAW_MESSAGE) {
            _handleWithdrawMessage(_messageBody);
        } else {
            revert InvalidMessageType(messageType);
        }
    }

    /**
     * @dev Handle withdrawal message from Rari (unlock tokens)
     */
    function _handleWithdrawMessage(
        bytes calldata _messageBody
    ) internal {
        Storage storage $ = getStorage();

        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.decodeWithdrawMessage(_messageBody);

        // Get source token from synthetic token mapping
        address sourceToken = $.syntheticToSource[message.syntheticToken];
        if (sourceToken == address(0)) {
            revert InvalidSyntheticToken(message.syntheticToken);
        }

        // Unlock tokens for user to claim
        $.unlockedBalanceOf[message.recipient][sourceToken] += message.amount;
        $.totalUnlocked[sourceToken] += message.amount;

        emit WithdrawMessageReceived(message.recipient, sourceToken, message.amount);
    }

    /**
     * @dev Claim unlocked tokens (Espresso pattern)
     */
    function claim(address token, uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.unlockedBalanceOf[msg.sender][token] < amount) {
            revert InsufficientUnlockedBalance(
                msg.sender, uint256(uint160(token)), amount, $.unlockedBalanceOf[msg.sender][token]
            );
        }

        $.unlockedBalanceOf[msg.sender][token] -= amount;
        $.totalWithdrawn[token] += amount;

        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Claim(msg.sender, token, amount);
    }

    /**
     * @dev Direct withdrawal from deposited balance (owner only - for emergencies)
     */
    function withdraw(address token, uint256 amount, address user) external onlyOwner nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.balanceOf[user][token] < amount) {
            revert InsufficientBalance(user, uint256(uint160(token)), amount, $.balanceOf[user][token]);
        }

        $.balanceOf[user][token] -= amount;

        if (token == address(0)) {
            payable(user).transfer(amount);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }

        emit Withdraw(user, token, amount);
    }

    /**
     * @dev Unlock tokens for withdrawal (owner only - for cross-chain unlocks)
     */
    function unlock(address token, uint256 amount, address user) external onlyOwner {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        if ($.balanceOf[user][token] < amount) {
            revert InsufficientBalance(user, uint256(uint160(token)), amount, $.balanceOf[user][token]);
        }

        $.balanceOf[user][token] -= amount;
        $.unlockedBalanceOf[user][token] += amount;

        emit Unlock(user, token, amount);
    }

    // =============================================================
    //                  ADMINISTRATIVE FUNCTIONS
    // =============================================================

    /**
     * @dev Add token to whitelist
     */
    function addWhitelistedToken(
        address token
    ) external onlyOwner {
        Storage storage $ = getStorage();

        if ($.whitelistedTokens[token]) {
            revert TokenAlreadyWhitelisted(token);
        }

        $.whitelistedTokens[token] = true;
        $.tokenList.push(token);

        emit TokenWhitelisted(token);
    }

    /**
     * @dev Add token to whitelist (legacy alias)  
     */
    function addToken(address token) external onlyOwner {
        Storage storage $ = getStorage();

        if ($.whitelistedTokens[token]) {
            revert TokenAlreadyWhitelisted(token);
        }

        $.whitelistedTokens[token] = true;
        $.tokenList.push(token);

        emit TokenWhitelisted(token);
    }

    /**
     * @dev Remove token from whitelist
     */
    function removeToken(
        address token
    ) external onlyOwner {
        Storage storage $ = getStorage();

        if (!$.whitelistedTokens[token]) {
            revert TokenNotFound(token);
        }

        $.whitelistedTokens[token] = false;

        // Remove from tokenList array
        for (uint256 i = 0; i < $.tokenList.length; i++) {
            if ($.tokenList[i] == token) {
                $.tokenList[i] = $.tokenList[$.tokenList.length - 1];
                $.tokenList.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /**
     * @dev Set cross-chain token mapping (Espresso pattern)
     */
    function setTokenMapping(address sourceToken, address syntheticToken) external onlyOwner {
        Storage storage $ = getStorage();

        $.sourceToSynthetic[sourceToken] = syntheticToken;
        $.syntheticToSource[syntheticToken] = sourceToken;

        emit TokenMappingSet(sourceToken, syntheticToken);
    }

    /**
     * @dev Update cross-chain configuration
     */
    function updateCrossChainConfig(uint32 _destinationDomain, address _destinationBalanceManager) external onlyOwner {
        Storage storage $ = getStorage();

        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;

        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }

    /**
     * @dev Update local domain (fix for incorrect domain during deployment)
     */
    function updateLocalDomain(uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();
        uint32 oldDomain = $.localDomain;
        $.localDomain = _localDomain;
        emit LocalDomainUpdated(oldDomain, _localDomain);
    }

    // =============================================================
    //                   YIELD VAULT MANAGEMENT
    // =============================================================

    /**
     * @dev Set ERC-4626 vault for a token (DRY: works for any token)
     * @param token The token address
     * @param vault The ERC-4626 vault address (or address(0) to remove)
     */
    function setVault(address token, address vault) external onlyOwner {
        Storage storage $ = getStorage();

        if (!$.whitelistedTokens[token] && token != address(0)) {
            revert TokenNotWhitelisted(token);
        }

        $.vaults[token] = vault;
        emit VaultSet(token, vault);
    }

    /**
     * @dev Set vault ratio (percentage deployed to vaults)
     * @param newRatio Ratio in basis points (e.g., 8000 = 80%)
     */
    function setVaultRatio(uint256 newRatio) external onlyOwner {
        if (newRatio > BASIS_POINTS) {
            revert("Vault ratio cannot exceed 100%");
        }

        Storage storage $ = getStorage();
        uint256 oldRatio = $.vaultRatio;
        $.vaultRatio = newRatio;

        emit VaultRatioUpdated(oldRatio, newRatio);
    }

    // =============================================================
    //                MERKLE SNAPSHOT SYSTEM (DYNAMIC)
    // =============================================================

    /**
     * @dev Snapshot data for a single token (DRY: same struct for all tokens)
     */
    struct TokenSnapshot {
        address token;
        bytes32 merkleRoot;
        uint256 totalSupply;      // Total synthetic supply on trading chain
        uint256 cumulativeYield;  // Cumulative yield from vault since inception
    }

    /**
     * @dev Update daily snapshots for all tokens (posted by indexer)
     * DYNAMIC: Accepts array of any length, works for 4 tokens or 400 tokens!
     * @param day The snapshot day (e.g., days since epoch)
     * @param snapshots Array of token snapshots
     */
    function updateDailySnapshot(
        uint256 day,
        TokenSnapshot[] calldata snapshots
    ) external onlyOwner {
        Storage storage $ = getStorage();

        // Clear previous token list for this day
        delete $.snapshotTokens[day];

        // Store each token's snapshot (DRY: same code for all tokens)
        for (uint256 i = 0; i < snapshots.length; i++) {
            TokenSnapshot calldata snap = snapshots[i];

            $.snapshotMerkleRoots[day][snap.token] = snap.merkleRoot;
            $.snapshotTotalSupply[day][snap.token] = snap.totalSupply;
            $.snapshotCumulativeYield[day][snap.token] = snap.cumulativeYield;
            $.snapshotTokens[day].push(snap.token);

            emit TokenSnapshotUpdated(day, snap.token, snap.merkleRoot, snap.totalSupply);
        }

        $.snapshotTimestamps[day] = block.timestamp;
        $.latestSnapshotDay = day;

        emit DailySnapshotUpdated(day, snapshots.length);
    }

    // =============================================================
    //                   YIELD CLAIMING (PER-TOKEN)
    // =============================================================

    /**
     * @dev Claim yield for a single token using Merkle proof
     * DRY: Same function works for ALL tokens (USDC, WETH, WBTC, etc.)
     * @param day The snapshot day to claim from
     * @param token The token to claim yield for
     * @param userBalance User's synthetic token balance on snapshot day
     * @param merkleProof Merkle proof for verification
     */
    function claimYield(
        uint256 day,
        address token,
        uint256 userBalance,
        bytes32[] calldata merkleProof
    ) external nonReentrant {
        Storage storage $ = getStorage();

        // Get snapshot data for this token
        bytes32 merkleRoot = $.snapshotMerkleRoots[day][token];
        if (merkleRoot == bytes32(0)) {
            revert("Snapshot not found for this day/token");
        }

        // Verify Merkle proof (KISS: simple leaf = hash(user, balance))
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, userBalance));
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) {
            revert("Invalid Merkle proof");
        }

        // Calculate user's yield share (per-token distribution)
        uint256 totalSupply = $.snapshotTotalSupply[day][token];
        uint256 vaultYield = $.snapshotCumulativeYield[day][token];

        if (totalSupply == 0 || userBalance == 0) {
            revert("No yield to claim");
        }

        // Pro-rata yield: (totalYield × userBalance) / totalSupply
        uint256 userYield = (vaultYield * userBalance) / totalSupply;

        // Check if already claimed
        uint256 alreadyClaimed = $.userClaimedYield[msg.sender][token];
        if (userYield <= alreadyClaimed) {
            revert("Yield already claimed");
        }

        uint256 claimableYield = userYield - alreadyClaimed;
        $.userClaimedYield[msg.sender][token] = userYield;

        // Withdraw from vault or direct transfer (DRY: works for any token)
        _withdrawYield(token, claimableYield, msg.sender);

        emit YieldClaimed(msg.sender, token, claimableYield, day);
    }

    /**
     * @dev Claim proof for batch claiming
     */
    struct ClaimProof {
        address token;
        uint256 userBalance;
        bytes32[] merkleProof;
    }

    /**
     * @dev Batch claim yield for multiple tokens (more gas-efficient)
     * @param day The snapshot day to claim from
     * @param proofs Array of claim proofs for different tokens
     */
    function claimYieldBatch(
        uint256 day,
        ClaimProof[] calldata proofs
    ) external nonReentrant {
        for (uint256 i = 0; i < proofs.length; i++) {
            ClaimProof calldata proof = proofs[i];

            Storage storage $ = getStorage();

            // Get snapshot data for this token
            bytes32 merkleRoot = $.snapshotMerkleRoots[day][proof.token];
            if (merkleRoot == bytes32(0)) {
                continue; // Skip if no snapshot
            }

            // Verify Merkle proof
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, proof.userBalance));
            if (!MerkleProof.verify(proof.merkleProof, merkleRoot, leaf)) {
                continue; // Skip invalid proofs
            }

            // Calculate yield
            uint256 totalSupply = $.snapshotTotalSupply[day][proof.token];
            uint256 vaultYield = $.snapshotCumulativeYield[day][proof.token];

            if (totalSupply == 0 || proof.userBalance == 0) {
                continue; // Skip if no yield
            }

            uint256 userYield = (vaultYield * proof.userBalance) / totalSupply;
            uint256 alreadyClaimed = $.userClaimedYield[msg.sender][proof.token];

            if (userYield <= alreadyClaimed) {
                continue; // Skip if already claimed
            }

            uint256 claimableYield = userYield - alreadyClaimed;
            $.userClaimedYield[msg.sender][proof.token] = userYield;

            // Withdraw yield
            _withdrawYield(proof.token, claimableYield, msg.sender);

            emit YieldClaimed(msg.sender, proof.token, claimableYield, day);
        }
    }

    /**
     * @dev Internal function to withdraw yield from vault or direct transfer
     * DRY: Generic withdrawal that works for any token
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     * @param recipient The recipient address
     */
    function _withdrawYield(
        address token,
        uint256 amount,
        address recipient
    ) internal {
        Storage storage $ = getStorage();
        address vault = $.vaults[token];

        if (vault != address(0)) {
            // Withdraw from ERC-4626 vault
            IERC4626(vault).withdraw(amount, recipient, address(this));
        } else {
            // Direct transfer (if no vault configured)
            if (token == address(0)) {
                payable(recipient).transfer(amount);
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        }
    }

    // =============================================================
    //                      VIEW FUNCTIONS
    // =============================================================

    function getBalance(address user, address token) external view returns (uint256) {
        return getStorage().balanceOf[user][token];
    }

    function getUnlockedBalance(address user, address token) external view returns (uint256) {
        return getStorage().unlockedBalanceOf[user][token];
    }

    function isTokenWhitelisted(
        address token
    ) external view returns (bool) {
        return getStorage().whitelistedTokens[token] || token == address(0);
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return getStorage().tokenList;
    }

    function getTokenCount() external view returns (uint256) {
        return getStorage().tokenList.length;
    }

    function getUserNonce(
        address user
    ) external view returns (uint256) {
        return getStorage().userNonces[user];
    }

    function isMessageProcessed(
        bytes32 messageId
    ) external view returns (bool) {
        return getStorage().processedMessages[messageId];
    }

    function getTokenMapping(
        address sourceToken
    ) external view returns (address) {
        return getStorage().sourceToSynthetic[sourceToken];
    }

    function getReverseTokenMapping(
        address syntheticToken
    ) external view returns (address) {
        return getStorage().syntheticToSource[syntheticToken];
    }

    function getCrossChainConfig()
        external
        view
        returns (uint32 destinationDomain, address destinationBalanceManager)
    {
        Storage storage $ = getStorage();
        return ($.destinationDomain, $.destinationBalanceManager);
    }

    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    function getDestinationConfig() external view returns (uint32 destinationDomain, address destinationBalanceManager) {
        Storage storage $ = getStorage();
        return ($.destinationDomain, $.destinationBalanceManager);
    }

    /**
     * @dev Get cross-chain configuration
     */
    function getCrossChainInfo() external view returns (
        address mailbox,
        uint32 localDomain,
        uint32 destinationDomain,
        address destinationBalanceManager
    ) {
        Storage storage $ = getStorage();
        return (
            $.mailbox,
            $.localDomain,
            $.destinationDomain,
            $.destinationBalanceManager
        );
    }

    /**
     * @dev Admin function to update cross-chain configuration (post-deployment)
     */
    function updateCrossChainConfig(
        address _mailbox,
        uint32 _destinationDomain,
        address _destinationBalanceManager
    ) external onlyOwner {
        Storage storage $ = getStorage();
        $.messageHandler = _mailbox;
        $.mailbox = _mailbox;
        $.destinationDomain = _destinationDomain;
        $.destinationBalanceManager = _destinationBalanceManager;

        emit DestinationChainConfigUpdated(false, _mailbox);
        emit CrossChainConfigUpdated(_destinationDomain, _destinationBalanceManager);
    }


    // =============================================================
    //                    LEGACY COMPATIBILITY
    // =============================================================

    // Maintain compatibility with existing interfaces
    function balanceOf(address user, address token) external view returns (uint256) {
        return getStorage().balanceOf[user][token];
    }

    function unlockedBalanceOf(address user, address token) external view returns (uint256) {
        return getStorage().unlockedBalanceOf[user][token];
    }

    function whitelistedTokens(
        address token
    ) external view returns (bool) {
        return getStorage().whitelistedTokens[token];
    }

    function tokenList(
        uint256 index
    ) external view returns (address) {
        return getStorage().tokenList[index];
    }

    // =============================================================
    //              YIELD SYSTEM VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev Get vault address for a token
     */
    function getVault(address token) external view returns (address) {
        return getStorage().vaults[token];
    }

    /**
     * @dev Get vault shares owned by ChainBalanceManager for a token
     */
    function getVaultShares(address token) external view returns (uint256) {
        return getStorage().vaultShares[token];
    }

    /**
     * @dev Get current vault ratio
     */
    function getVaultRatio() external view returns (uint256) {
        Storage storage $ = getStorage();
        return $.vaultRatio > 0 ? $.vaultRatio : DEFAULT_VAULT_RATIO;
    }

    /**
     * @dev Get snapshot data for a specific day and token
     */
    function getSnapshot(
        uint256 day,
        address token
    ) external view returns (
        bytes32 merkleRoot,
        uint256 totalSupply,
        uint256 cumulativeYield
    ) {
        Storage storage $ = getStorage();
        return (
            $.snapshotMerkleRoots[day][token],
            $.snapshotTotalSupply[day][token],
            $.snapshotCumulativeYield[day][token]
        );
    }

    /**
     * @dev Get all tokens that had snapshots on a specific day
     */
    function getSnapshotTokens(uint256 day) external view returns (address[] memory) {
        return getStorage().snapshotTokens[day];
    }

    /**
     * @dev Get snapshot timestamp
     */
    function getSnapshotTimestamp(uint256 day) external view returns (uint256) {
        return getStorage().snapshotTimestamps[day];
    }

    /**
     * @dev Get latest snapshot day
     */
    function getLatestSnapshotDay() external view returns (uint256) {
        return getStorage().latestSnapshotDay;
    }

    /**
     * @dev Get user's claimed yield for a token
     */
    function getUserClaimedYield(address user, address token) external view returns (uint256) {
        return getStorage().userClaimedYield[user][token];
    }

    /**
     * @dev Calculate claimable yield for a user (requires off-chain balance data)
     * @param day The snapshot day
     * @param token The token
     * @param userBalance User's synthetic token balance on snapshot day
     * @return claimable The amount of yield that can be claimed
     */
    function calculateClaimableYield(
        uint256 day,
        address token,
        uint256 userBalance
    ) external view returns (uint256 claimable) {
        Storage storage $ = getStorage();

        uint256 totalSupply = $.snapshotTotalSupply[day][token];
        uint256 vaultYield = $.snapshotCumulativeYield[day][token];

        if (totalSupply == 0 || userBalance == 0) {
            return 0;
        }

        uint256 userYield = (vaultYield * userBalance) / totalSupply;
        uint256 alreadyClaimed = $.userClaimedYield[msg.sender][token];

        if (userYield <= alreadyClaimed) {
            return 0;
        }

        return userYield - alreadyClaimed;
    }

    /**
     * @dev Get total deposited, withdrawn, and unlocked for a token
     */
    function getTokenStats(address token) external view returns (
        uint256 totalDeposited,
        uint256 totalWithdrawn,
        uint256 totalUnlocked
    ) {
        Storage storage $ = getStorage();
        return (
            $.totalDeposited[token],
            $.totalWithdrawn[token],
            $.totalUnlocked[token]
        );
    }
}
