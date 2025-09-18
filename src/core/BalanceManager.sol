// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IBalanceManager} from "./interfaces/IBalanceManager.sol";

import {IMailbox} from "./interfaces/IMailbox.sol";
import {IMessageRecipient} from "./interfaces/IMessageRecipient.sol";
import {Currency} from "./libraries/Currency.sol";

import {HyperlaneMessages} from "./libraries/HyperlaneMessages.sol";
import {BalanceManagerStorage} from "./storages/BalanceManagerStorage.sol";

import {TokenRegistry} from "./TokenRegistry.sol";
import {ISyntheticERC20} from "./interfaces/ISyntheticERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/Test.sol";

contract BalanceManager is
    IBalanceManager,
    IMessageRecipient,
    BalanceManagerStorage,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Custom errors
    error IncorrectEthAmount(uint256 expected, uint256 actual);
    error EthSentForErc20Deposit();
    error FeeExceedsTransferAmount(uint256 fee, uint256 amount);
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _feeReceiver,
        uint256 _feeMaker,
        uint256 _feeTaker
    ) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Storage storage $ = getStorage();
        $.feeReceiver = _feeReceiver;
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
        $.feeUnit = 1000;
    }

    function setPoolManager(
        address _poolManager
    ) external onlyOwner {
        getStorage().poolManager = _poolManager;
        emit PoolManagerSet(_poolManager);
    }

    function setMailbox(
        address _mailbox
    ) external onlyOwner {
        getStorage().mailbox = _mailbox;
    }

    // Allow owner to set authorized operators (e.g., Router)
    function setAuthorizedOperator(address operator, bool approved) external {
        Storage storage $ = getStorage();

        if (msg.sender != owner() && msg.sender != $.poolManager) {
            revert UnauthorizedCaller(msg.sender);
        }

        $.authorizedOperators[operator] = approved;
        emit OperatorSet(operator, approved);
    }

    function setFees(uint256 _feeMaker, uint256 _feeTaker) external onlyOwner {
        Storage storage $ = getStorage();
        $.feeMaker = _feeMaker;
        $.feeTaker = _feeTaker;
    }

    // Allow anyone to check balanceOf
    function getBalance(address user, Currency currency) external view returns (uint256) {
        return getStorage().balanceOf[user][currency.toId()];
    }

    function getLockedBalance(address user, address operator, Currency currency) external view returns (uint256) {
        return getStorage().lockedBalanceOf[user][operator][currency.toId()];
    }

    function deposit(Currency currency, uint256 amount, address sender, address user) public payable nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        if (msg.sender != sender && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if (currency.isAddressZero()) {
            if (msg.value != amount) {
                revert IncorrectEthAmount(amount, msg.value);
            }
        } else {
            if (msg.value != 0) {
                revert EthSentForErc20Deposit();
            }

            currency.transferFrom(sender, address(this), amount);
        }

        uint256 currencyId = currency.toId();

        unchecked {
            $.balanceOf[user][currencyId] += amount;
        }

        emit Deposit(user, currencyId, amount);
    }

    function depositAndLock(
        Currency currency,
        uint256 amount,
        address user,
        address orderBook
    ) external nonReentrant returns (uint256) {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();

        // Verify if the caller is the user or an authorized operator
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        // Transfer tokens directly from sender to this contract
        currency.transferFrom(user, address(this), amount);

        // Credit directly to locked balance, bypassing the regular balance
        uint256 currencyId = currency.toId();

        unchecked {
            $.lockedBalanceOf[user][orderBook][currencyId] += amount;
        }

        emit Deposit(user, currencyId, amount);

        return amount;
    }

    function withdraw(Currency currency, uint256 amount) external {
        withdraw(currency, amount, msg.sender);
    }

    // Withdraw tokens
    function withdraw(Currency currency, uint256 amount, address user) public nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        // Verify if the caller is the user or an authorized operator
        if (msg.sender != user && !$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, $.balanceOf[user][currency.toId()]);
        }
        $.balanceOf[user][currency.toId()] -= amount;
        currency.transfer(user, amount);
        emit Withdrawal(user, currency.toId(), amount);
    }

    function lock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, msg.sender);
    }

    function lock(address user, Currency currency, uint256 amount, address orderBook) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        _lock(user, currency, amount, orderBook);
    }

    function _lock(address user, Currency currency, uint256 amount, address locker) private {
        Storage storage $ = getStorage();

        if ($.balanceOf[user][currency.toId()] < amount) {
            revert InsufficientBalance(user, currency.toId(), amount, $.balanceOf[user][currency.toId()]);
        }

        $.balanceOf[user][currency.toId()] -= amount;
        $.lockedBalanceOf[user][locker][currency.toId()] += amount;

        emit Lock(user, currency.toId(), amount);
    }

    function unlock(address user, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();

        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }

        if ($.lockedBalanceOf[user][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                user, currency.toId(), amount, $.lockedBalanceOf[user][msg.sender][currency.toId()]
            );
        }

        $.lockedBalanceOf[user][msg.sender][currency.toId()] -= amount;
        $.balanceOf[user][currency.toId()] += amount;

        emit Unlock(user, currency.toId(), amount);
    }

    function transferOut(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, $.balanceOf[sender][currency.toId()]);
        }

        currency.transfer(receiver, amount);

        $.balanceOf[sender][currency.toId()] -= amount;
    }

    function transferLockedFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.lockedBalanceOf[sender][msg.sender][currency.toId()] < amount) {
            revert InsufficientBalance(
                sender, currency.toId(), amount, $.lockedBalanceOf[sender][msg.sender][currency.toId()]
            );
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeTaker / _feeUnit();
        if (feeAmount > amount) {
            revert FeeExceedsTransferAmount(feeAmount, amount);
        }

        // Deduct fee and update balances
        $.lockedBalanceOf[sender][msg.sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currency.toId()] += feeAmount;

        emit TransferLockedFrom(msg.sender, sender, receiver, currency.toId(), amount, feeAmount);
    }

    function transferFrom(address sender, address receiver, Currency currency, uint256 amount) external {
        Storage storage $ = getStorage();
        if (!$.authorizedOperators[msg.sender]) {
            revert UnauthorizedOperator(msg.sender);
        }
        if ($.balanceOf[sender][currency.toId()] < amount) {
            revert InsufficientBalance(sender, currency.toId(), amount, $.balanceOf[sender][currency.toId()]);
        }

        // Determine fee based on the role (maker/taker)
        uint256 feeAmount = amount * $.feeMaker / _feeUnit();
        if (feeAmount > amount) {
            revert FeeExceedsTransferAmount(feeAmount, amount);
        }

        // Deduct fee and update balances
        $.balanceOf[sender][currency.toId()] -= amount;
        uint256 amountAfterFee = amount - feeAmount;
        $.balanceOf[receiver][currency.toId()] += amountAfterFee;

        // Transfer the fee to the feeReceiver
        $.balanceOf[$.feeReceiver][currency.toId()] += feeAmount;

        emit TransferFrom(msg.sender, sender, receiver, currency.toId(), amount, feeAmount);
    }

    // Add public getters for fees and feeReceiver
    function feeMaker() external view returns (uint256) {
        return getStorage().feeMaker;
    }

    function feeTaker() external view returns (uint256) {
        return getStorage().feeTaker;
    }

    function feeReceiver() external view returns (address) {
        return getStorage().feeReceiver;
    }

    function getFeeUnit() external view returns (uint256) {
        return _feeUnit();
    }

    function _feeUnit() private view returns (uint256) {
        return getStorage().feeUnit;
    }

    // =============================================================
    //                   CROSS-CHAIN FUNCTIONS
    // =============================================================

    // Initialize cross-chain functionality
    function initializeCrossChain(address _mailbox, uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();
        if ($.mailbox != address(0)) {
            revert AlreadyInitialized();
        }

        $.mailbox = _mailbox;
        $.localDomain = _localDomain;

        emit CrossChainInitialized(_mailbox, _localDomain);
    }

    // Update cross-chain configuration (for upgrades)
    function updateCrossChainConfig(address _mailbox, uint32 _localDomain) external onlyOwner {
        Storage storage $ = getStorage();

        address oldMailbox = $.mailbox;
        uint32 oldDomain = $.localDomain;

        $.mailbox = _mailbox;
        $.localDomain = _localDomain;

        emit CrossChainConfigUpdated(oldMailbox, _mailbox, oldDomain, _localDomain);
    }

    // Set TokenRegistry for synthetic token mapping
    function setTokenRegistry(
        address _tokenRegistry
    ) external onlyOwner {
        Storage storage $ = getStorage();
        if (_tokenRegistry == address(0)) {
            revert InvalidTokenRegistry();
        }
        $.tokenRegistry = _tokenRegistry;
    }

    // Set ChainBalanceManager for a source chain
    function setChainBalanceManager(uint32 chainId, address chainBalanceManager) external onlyOwner {
        Storage storage $ = getStorage();
        $.chainBalanceManagers[chainId] = chainBalanceManager;
        emit ChainBalanceManagerSet(chainId, chainBalanceManager);
    }

    // Cross-chain message handler (receives deposit messages from ChainBalanceManager)
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _messageBody) external payable override {
        Storage storage $ = getStorage();
        if (msg.sender != $.mailbox) {
            revert OnlyMailbox();
        }

        // Verify sender is authorized ChainBalanceManager
        address expectedSender = $.chainBalanceManagers[_origin];
        if (expectedSender == address(0)) {
            revert UnknownOriginChain(_origin);
        }
        bytes32 expectedSenderBytes = bytes32(uint256(uint160(expectedSender)));
        if (_sender != expectedSenderBytes) {
            revert InvalidSender(expectedSenderBytes, _sender);
        }

        // Decode message type
        uint8 messageType = abi.decode(_messageBody, (uint8));

        if (messageType == HyperlaneMessages.DEPOSIT_MESSAGE) {
            _handleDepositMessage(_origin, _messageBody);
        } else {
            revert("Unknown message type");
        }
    }

    // Handle deposit notification from source chain
    function _handleDepositMessage(uint32 _origin, bytes calldata _messageBody) internal {
        HyperlaneMessages.DepositMessage memory message = abi.decode(_messageBody, (HyperlaneMessages.DepositMessage));

        Storage storage $ = getStorage();

        // Replay protection
        bytes32 messageId = keccak256(abi.encodePacked(_origin, message.user, message.nonce));
        if ($.processedMessages[messageId]) {
            revert MessageAlreadyProcessed(messageId);
        }
        $.processedMessages[messageId] = true;

        // Mint synthetic tokens directly to user
        Currency syntheticCurrency = Currency.wrap(message.syntheticToken);
        uint256 currencyId = syntheticCurrency.toId();

        // Mint actual ERC20 synthetic tokens to BalanceManager (vault)
        ISyntheticERC20 syntheticToken = ISyntheticERC20(message.syntheticToken);
        syntheticToken.mint(address(this), message.amount);

        // Update internal balance tracking for CLOB system
        $.balanceOf[message.user][currencyId] += message.amount;

        emit CrossChainDepositReceived(message.user, syntheticCurrency, message.amount, _origin);
        emit Deposit(message.user, currencyId, message.amount);
    }

    // Request withdrawal to source chain (burns synthetic, sends message)
    function requestWithdraw(
        Currency syntheticCurrency,
        uint256 amount,
        uint32 targetChainId,
        address recipient
    ) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }

        Storage storage $ = getStorage();
        address targetChainBM = $.chainBalanceManagers[targetChainId];
        if (targetChainBM == address(0)) {
            revert TargetChainNotSupported(targetChainId);
        }

        // Burn synthetic tokens and update internal balance
        uint256 currencyId = syntheticCurrency.toId();
        if ($.balanceOf[msg.sender][currencyId] < amount) {
            revert InsufficientBalance(msg.sender, currencyId, amount, $.balanceOf[msg.sender][currencyId]);
        }

        // Burn actual ERC20 synthetic tokens from BalanceManager (vault)
        ISyntheticERC20 syntheticToken = ISyntheticERC20(Currency.unwrap(syntheticCurrency));
        syntheticToken.burn(address(this), amount);

        // Update internal balance tracking
        $.balanceOf[msg.sender][currencyId] -= amount;

        // Get user nonce and increment
        uint256 currentNonce = $.userNonces[msg.sender]++;

        // Create withdraw message
        HyperlaneMessages.WithdrawMessage memory message = HyperlaneMessages.WithdrawMessage({
            messageType: HyperlaneMessages.WITHDRAW_MESSAGE,
            syntheticToken: Currency.unwrap(syntheticCurrency),
            recipient: recipient,
            amount: amount,
            targetChainId: targetChainId,
            nonce: currentNonce
        });

        // Send cross-chain message
        bytes memory messageBody = abi.encode(message);
        bytes32 recipientAddress = bytes32(uint256(uint160(targetChainBM)));

        IMailbox($.mailbox).dispatch(targetChainId, recipientAddress, messageBody);

        emit CrossChainWithdrawSent(msg.sender, syntheticCurrency, amount, targetChainId);
        emit Withdrawal(msg.sender, currencyId, amount);
    }

    // View functions for cross-chain
    function getMailboxConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    function getChainBalanceManager(
        uint32 chainId
    ) external view returns (address) {
        return getStorage().chainBalanceManagers[chainId];
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

    // Deposit local tokens and mint synthetic tokens on the same chain
    function depositLocal(address token, uint256 amount, address recipient) external nonReentrant {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (token == address(0)) {
            revert InvalidTokenAddress();
        }
        if (recipient == address(0)) {
            revert InvalidRecipientAddress();
        }

        Storage storage $ = getStorage();
        if ($.tokenRegistry == address(0)) {
            revert TokenRegistryNotSet();
        }

        uint32 currentChain = _getCurrentChainId();

        // Use TokenRegistry to validate local mapping (sourceChain == targetChain)
        if (!TokenRegistry($.tokenRegistry).isTokenMappingActive(currentChain, token, currentChain)) {
            revert TokenNotSupportedForLocalDeposits(token);
        }

        // Get synthetic token address from TokenRegistry
        address syntheticToken = TokenRegistry($.tokenRegistry).getSyntheticToken(currentChain, token, currentChain);

        // Convert amount using TokenRegistry decimal conversion
        uint256 syntheticAmount =
            TokenRegistry($.tokenRegistry).convertAmountForMapping(currentChain, token, currentChain, amount, true);

        // Transfer real tokens to this contract (vault them)
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Mint synthetic tokens to BalanceManager (vault)
        ISyntheticERC20(syntheticToken).mint(address(this), syntheticAmount);

        // Update internal balance tracking for CLOB system
        uint256 currencyId = Currency.wrap(syntheticToken).toId();
        $.balanceOf[recipient][currencyId] += syntheticAmount;

        emit LocalDeposit(recipient, token, syntheticToken, amount, syntheticAmount);
        emit Deposit(recipient, currencyId, syntheticAmount);
    }

    /**
     * @dev Get current chain ID
     */
    function _getCurrentChainId() internal view returns (uint32) {
        return uint32(block.chainid);
    }

    /**
     * @dev Get TokenRegistry address
     */
    function getTokenRegistry() external view returns (address) {
        return getStorage().tokenRegistry;
    }

    /**
     * @dev Get cross-chain configuration
     */
    function getCrossChainConfig() external view returns (address mailbox, uint32 localDomain) {
        Storage storage $ = getStorage();
        return ($.mailbox, $.localDomain);
    }

    // Cross-chain events
    event CrossChainDepositReceived(
        address indexed user, Currency indexed currency, uint256 amount, uint32 sourceChain
    );
    event CrossChainWithdrawSent(address indexed user, Currency indexed currency, uint256 amount, uint32 targetChain);
    event ChainBalanceManagerSet(uint32 indexed chainId, address indexed chainBalanceManager);
    event CrossChainInitialized(address indexed mailbox, uint32 indexed localDomain);
    event CrossChainConfigUpdated(address indexed oldMailbox, address indexed newMailbox, uint32 oldDomain, uint32 newDomain);

    // Local deposit event
    event LocalDeposit(
        address indexed recipient,
        address indexed sourceToken,
        address indexed syntheticToken,
        uint256 sourceAmount,
        uint256 syntheticAmount
    );
}
