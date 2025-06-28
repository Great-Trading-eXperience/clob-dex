// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FaucetStorage} from "./FaucetStorage.sol";

contract Faucet is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, FaucetStorage {
    event AddToken(address token);
    event UpdateFaucetAmount(uint256 amount);
    event UpdateFaucetCooldown(uint256 cooldown);
    event RequestToken(address requester, address receiver, address token);
    event DepositToken(address depositor, address token, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        
        Storage storage $ = getStorage();
        $.owner = _owner;
        $.faucetAmount = 0;
        $.faucetCooldown = 0;
    }

    function addToken(address _token) public onlyOwner {
        Storage storage $ = getStorage();

        for (uint256 i = 0; i < $.availableTokens.length; i++) {
            if (_token == $.availableTokens[i]) {
                revert("The token has already exist");
            }
        }

        $.availableTokens.push(_token);

        emit AddToken(_token);
    }

    function getAvailableTokensLength() view public returns(uint256) {
        return getStorage().availableTokens.length;
    }

    function getAvailableToken(uint256 index) view public returns(address) {
        return getStorage().availableTokens[index];
    }

    function updateFaucetAmount(uint256 _faucetAmount) public onlyOwner {
        Storage storage $ = getStorage();
        $.faucetAmount = _faucetAmount;
        emit UpdateFaucetAmount(_faucetAmount);
    }
    
    function updateFaucetCooldown(uint256 _faucetCooldown) public onlyOwner {
        Storage storage $ = getStorage();
        $.faucetCooldown = _faucetCooldown;
        emit UpdateFaucetCooldown(_faucetCooldown);
    }

    function getLastRequestTime() public view returns (uint256) {
        return getStorage().lastRequestTime[msg.sender];
    }
    
    function getAvailabilityTime() public view returns (uint256) {
        Storage storage $ = getStorage();
        return $.lastRequestTime[msg.sender] + $.faucetCooldown;
    }

    function getCooldown() public view returns (uint256) {
        return getStorage().faucetCooldown;
    }

    function getFaucetAmount() public view returns (uint256) {
        return getStorage().faucetAmount;
    }
    
    function getCurrentTimestamp() public view returns (uint256) {
        return block.timestamp;
    }

    function requestToken(address _receiver, address _token) public nonReentrant {
        Storage storage $ = getStorage();
        require($.faucetAmount > 0, "Faucet amount isn't set yet");
        require($.faucetCooldown > 0, "Faucet cooldown isn't set yet");
        require(block.timestamp > $.lastRequestTime[msg.sender], "Please wait until the cooldown time is passed");
        require(IERC20(_token).balanceOf(address(this)) > $.faucetAmount, "The amount of balance is not enough");

        bool result = IERC20(_token).transfer(_receiver, $.faucetAmount);
        require(result, "The transfer process doesn't executed successfully");

        $.lastRequestTime[msg.sender] = block.timestamp;

        emit RequestToken(msg.sender, _receiver, _token);
    }

    function drainWallet(address _token) public nonReentrant {
        uint256 balance = IERC20(_token).balanceOf(msg.sender);
        bool success = IERC20(_token).transferFrom(msg.sender, address(this), balance);
        require(success, "Transfer failed");
    }

    function depositToken(address _token, uint256 _amount) public nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");
        
        Storage storage $ = getStorage();
        bool exists = false;
        for (uint256 i = 0; i < $.availableTokens.length; i++) {
            if (_token == $.availableTokens[i]) {
                exists = true;
                break;
            }
        }
        require(exists, "Token not supported by faucet");

        bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        require(success, "Transfer failed");

        emit DepositToken(msg.sender, _token, _amount);
    }
}