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
import {IVaultFactory} from "../vaults/interfaces/IVaultFactory.sol";
import {IVault} from "../vaults/interfaces/IVault.sol";

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
    event VaultFactorySet(address indexed vaultFactory);
    event VaultCreated(address indexed token, address indexed vault);
    event AllocationSettingsUpdated(address indexed token, uint256 keepBps, uint256 vaultBps);
    event Rebalanced(address indexed token, uint256 keepAmount, uint256 vaultAmount);

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
            revert InvalidChainConfiguration();
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
        revert InvalidChainConfiguration();
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
    //                    VAULT MANAGEMENT
    // =============================================================

    /**
     * @dev Set the vault factory address
     * @param _vaultFactory The vault factory address
     */
    function setVaultFactory(address _vaultFactory) external onlyOwner {
        if (_vaultFactory == address(0)) {
            revert ZeroAddress();
        }

        Storage storage $ = getStorage();
        $.vaultFactory = _vaultFactory;

        emit VaultFactorySet(_vaultFactory);
    }

    /**
     * @dev Create a vault for a token
     * @param token The token to create a vault for
     * @param lendingPool The lending pool address for yield generation
     */
    function createVault(address token, address lendingPool) external onlyOwner {
        Storage storage $ = getStorage();

        if ($.vaultFactory == address(0)) {
            revert ZeroAddress();
        }

        if ($.tokenVaults[token] != address(0)) {
            revert VaultAlreadyExists(token);
        }

        // Create vault through factory
        address vault = IVaultFactory($.vaultFactory).createVault(token, lendingPool);

        $.tokenVaults[token] = vault;

        emit VaultCreated(token, vault);
    }

    /**
     * @dev Set allocation settings for a token
     * @param token The token to set allocation for
     * @param keepBps Basis points to keep in ChainBalanceManager (e.g., 2000 = 20%)
     * @param vaultBps Basis points to allocate to vault (e.g., 8000 = 80%)
     */
    function setAllocationSettings(address token, uint256 keepBps, uint256 vaultBps) external onlyOwner {
        if (keepBps + vaultBps != 10000) {
            revert InvalidAllocation(keepBps, vaultBps);
        }

        Storage storage $ = getStorage();
        $.vaultAllocationBps[token] = vaultBps;

        emit AllocationSettingsUpdated(token, keepBps, vaultBps);
    }

    /**
     * @dev Set default allocation settings
     * @param keepBps Default basis points to keep (e.g., 2000 = 20%)
     * @param vaultBps Default basis points to vault (e.g., 8000 = 80%)
     */
    function setDefaultAllocation(uint256 keepBps, uint256 vaultBps) external onlyOwner {
        if (keepBps + vaultBps != 10000) {
            revert InvalidAllocation(keepBps, vaultBps);
        }

        Storage storage $ = getStorage();
        $.defaultKeepBps = keepBps;
        $.defaultVaultBps = vaultBps;
    }

    /**
     * @dev Rebalance funds between ChainBalanceManager and vault
     * @param token The token to rebalance
     */
    function rebalance(address token) external onlyOwner nonReentrant {
        Storage storage $ = getStorage();

        address vault = $.tokenVaults[token];
        if (vault == address(0)) {
            revert VaultNotFound(token);
        }

        // Get allocation settings
        uint256 vaultBps = $.vaultAllocationBps[token];
        if (vaultBps == 0) {
            vaultBps = $.defaultVaultBps;
        }

        uint256 keepBps = 10000 - vaultBps;

        // Get current amounts
        uint256 currentBalance = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));

        uint256 vaultBalance = IVault(vault).totalAssets();

        // Calculate total available funds (including vault balance with yield)
        uint256 totalDeposited = $.totalDeposited[token];
        uint256 totalWithdrawn = $.totalWithdrawn[token];
        uint256 totalUnlocked = $.totalUnlocked[token];

        // Available = deposited - withdrawn - unlocked + vault yield
        // The vault balance includes both principal and generated yield
        uint256 totalAvailableFromDeposits = totalDeposited - totalWithdrawn - totalUnlocked;

        // Total available should account for actual funds: what's in manager + what's in vault
        uint256 totalActualFunds = currentBalance + vaultBalance;

        // Use the actual total funds for rebalancing to include yield
        uint256 totalAvailable = totalActualFunds;

        // Calculate target amounts
        uint256 targetKeep = (totalAvailable * keepBps) / 10000;
        uint256 targetVault = (totalAvailable * vaultBps) / 10000;

        // Rebalance if needed
        if (currentBalance > targetKeep) {
            // Transfer excess to vault
            uint256 excess = currentBalance - targetKeep;

            if (token != address(0)) {
                IERC20(token).safeIncreaseAllowance(vault, excess);
            }

            IVault(vault).deposit(excess);
        } else if (currentBalance < targetKeep && vaultBalance > 0) {
            // Withdraw from vault to meet target
            uint256 needed = targetKeep - currentBalance;
            uint256 toWithdraw = needed > vaultBalance ? vaultBalance : needed;

            IVault(vault).withdraw(toWithdraw, address(this));
        }

        emit Rebalanced(token, targetKeep, targetVault);
    }

    /**
     * @dev Get vault for a token
     * @param token The token to get vault for
     * @return The vault address
     */
    function getVault(address token) external view returns (address) {
        return getStorage().tokenVaults[token];
    }

    /**
     * @dev Get allocation settings for a token
     * @param token The token to get allocation for
     * @return keepBps Basis points to keep
     * @return vaultBps Basis points to vault
     */
    function getAllocationSettings(address token) external view returns (uint256 keepBps, uint256 vaultBps) {
        Storage storage $ = getStorage();
        vaultBps = $.vaultAllocationBps[token];

        if (vaultBps == 0) {
            vaultBps = $.defaultVaultBps;
        }

        keepBps = 10000 - vaultBps;
    }

    /**
     * @dev Get vault factory address
     * @return The vault factory address
     */
    function getVaultFactory() external view returns (address) {
        return getStorage().vaultFactory;
    }

    /**
     * @dev Withdraw all funds from a vault (emergency/owner only)
     * @param token The token whose vault to withdraw from
     */
    function withdrawAllFromVault(address token) external onlyOwner nonReentrant {
        Storage storage $ = getStorage();

        address vault = $.tokenVaults[token];
        if (vault == address(0)) {
            revert VaultNotFound(token);
        }

        // Get total assets in vault
        uint256 vaultBalance = IVault(vault).totalAssets();

        if (vaultBalance == 0) {
            revert ZeroAmount();
        }

        // Withdraw all funds from vault to ChainBalanceManager
        IVault(vault).withdraw(vaultBalance, address(this));

        emit Rebalanced(token, 0, 0);
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
}
