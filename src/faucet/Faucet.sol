// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {OwnableUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FaucetStorage} from "./FaucetStorage.sol";

interface IFaucetErrors {
    error TokenAlreadyExists(address token);
    error FaucetAmountNotSet();
    error FaucetCooldownNotSet();
    error CooldownNotPassed(uint256 availableAt);
    error InsufficientFaucetBalance(uint256 required, uint256 available);
    error TransferFailed();
    error ZeroAmount();
    error TokenNotSupported(address token);
    error InsufficientNativeBalance(uint256 required, uint256 available);
    error NativeTransferFailed();
    error IncorrectNativeAmount();
}

contract Faucet is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, FaucetStorage, IFaucetErrors {
    event AddToken(address token);
    event UpdateFaucetAmount(uint256 amount);
    event UpdateFaucetCooldown(uint256 cooldown);
    event RequestToken(address requester, address receiver, address token);
    event DepositToken(address depositor, address token, uint256 amount);

    address private constant NATIVE_TOKEN = address(0);

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
                revert TokenAlreadyExists(_token);
            }
        }

        $.availableTokens.push(_token);

        emit AddToken(_token);
    }

    function getAvailableTokensLength() public view returns(uint256) {
        return getStorage().availableTokens.length;
    }

    function getAvailableToken(uint256 index) public view returns(address) {
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
    
    function getNativeBalance() public view returns (uint256) {
        return address(this).balance;
    }
    
    function getTokenBalance(address _token) public view returns (uint256) {
        if (_token == NATIVE_TOKEN) {
            return address(this).balance;
        } else {
            return IERC20(_token).balanceOf(address(this));
        }
    }
    
    function isNativeToken(address _token) public pure returns (bool) {
        return _token == NATIVE_TOKEN;
    }

    function requestToken(address _receiver, address _token) public nonReentrant {
        Storage storage $ = getStorage();
        if ($.faucetAmount == 0) {
            revert FaucetAmountNotSet();
        }
        if ($.faucetCooldown == 0) {
            revert FaucetCooldownNotSet();
        }
        uint256 lastRequest = $.lastRequestTime[msg.sender];
        if (lastRequest != 0 && block.timestamp < lastRequest + $.faucetCooldown) {
            revert CooldownNotPassed(lastRequest + $.faucetCooldown);
        }
        
        if (_token == NATIVE_TOKEN) {
            // Handle native token (ETH)
            uint256 nativeBalance = address(this).balance;
            if (nativeBalance < $.faucetAmount) {
                revert InsufficientNativeBalance($.faucetAmount, nativeBalance);
            }
            
            (bool success, ) = payable(_receiver).call{value: $.faucetAmount}("");
            if (!success) {
                revert NativeTransferFailed();
            }
            
            emit RequestToken(msg.sender, _receiver, NATIVE_TOKEN);
        } else {
            // Handle ERC20 token
            uint256 faucetBalance = IERC20(_token).balanceOf(address(this));
            if (faucetBalance < $.faucetAmount) {
                revert InsufficientFaucetBalance($.faucetAmount, faucetBalance);
            }

            bool result = IERC20(_token).transfer(_receiver, $.faucetAmount);
            if (!result) {
                revert TransferFailed();
            }
            
            emit RequestToken(msg.sender, _receiver, _token);
        }

        $.lastRequestTime[msg.sender] = block.timestamp;
    }

    function depositToken(address _token, uint256 _amount) public payable nonReentrant {
        if (_amount == 0) {
            revert ZeroAmount();
        }
        
        Storage storage $ = getStorage();
        
        if (_token == NATIVE_TOKEN) {
            // Handle native token (ETH) deposit
            if (msg.value != _amount) {
                revert IncorrectNativeAmount();
            }
            
            emit DepositToken(msg.sender, NATIVE_TOKEN, _amount);
        } else {
            // Handle ERC20 token deposit
            if (msg.value != 0) {
                revert IncorrectNativeAmount();
            }
            
            bool exists = false;
            for (uint256 i = 0; i < $.availableTokens.length; i++) {
                if (_token == $.availableTokens[i]) {
                    exists = true;
                    break;
                }
            }
            if (!exists) {
                revert TokenNotSupported(_token);
            }

            bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
            if (!success) {
                revert TransferFailed();
            }

            emit DepositToken(msg.sender, _token, _amount);
        }
    }
    
    // Convenience function to deposit native token without specifying amount
    function depositNative() external payable nonReentrant {
        if (msg.value == 0) {
            revert ZeroAmount();
        }
        
        emit DepositToken(msg.sender, NATIVE_TOKEN, msg.value);
    }
    
    // Convenience function to request native token
    function requestNative(address _receiver) external nonReentrant {
        requestToken(_receiver, NATIVE_TOKEN);
    }
    
    // Allow contract to receive native tokens directly
    receive() external payable {
        emit DepositToken(msg.sender, NATIVE_TOKEN, msg.value);
    }
    
    // Fallback function
    fallback() external payable {
        emit DepositToken(msg.sender, NATIVE_TOKEN, msg.value);
    }
}