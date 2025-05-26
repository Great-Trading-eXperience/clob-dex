// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IGTXMarketMakerFactory} from "./../interfaces/IGTXMarketMakerFactory.sol";
import {GTXMarketMakerVault} from "./GTXMarketMakerVault.sol";
import {GTXMarketMakerFactoryStorage} from "./GTXMarketMakerFactoryStorage.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract GTXMarketMakerFactory is Initializable, OwnableUpgradeable, GTXMarketMakerFactoryStorage, IGTXMarketMakerFactory {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _veToken,
        address _gaugeController,
        address _router,
        address _poolManager,
        address _balanceManager,
        address _vaultImplementation
    ) public initializer {
        __Ownable_init(_owner);
        
        require(_veToken != address(0), "Zero veToken");
        require(_gaugeController != address(0), "Zero gaugeController");
        require(_router != address(0), "Zero router");
        require(_poolManager != address(0), "Zero poolManager");
        require(_balanceManager != address(0), "Zero balanceManager");
        require(_vaultImplementation != address(0), "Zero implementation");
        
        Storage storage $ = getStorage();
        
        $.veToken = _veToken;
        $.gaugeController = _gaugeController;
        $.router = _router;
        $.poolManager = _poolManager;
        $.balanceManager = _balanceManager;
        
        // Create the upgradable beacon for vaults
        UpgradeableBeacon beacon = new UpgradeableBeacon(_vaultImplementation, address(this));
        $.vaultBeacon = address(beacon);
        $.vaultImplementation = _vaultImplementation;
        
        // Set initial parameter constraints
        $.minTargetRatio = 1000;       // 10% minimum
        $.maxTargetRatio = 9000;       // 90% maximum
        $.minSpread = 5;               // 0.05% minimum
        $.maxSpread = 500;             // 5% maximum
        $.minOrderSize = 0.01 * 10**18; // 0.01 ETH minimum
        $.maxOrderSize = 100 * 10**18;  // 100 ETH maximum
        $.minSlippageTolerance = 10;    // 0.1% minimum
        $.maxSlippageTolerance = 200;   // 2% maximum
        $.minActiveOrders = 2;          // At least 2 orders
        $.maxActiveOrders = 100;        // Maximum 100 orders
        $.minRebalanceInterval = 5 minutes; // Minimum 5 minutes
        $.maxRebalanceInterval = 7 days;    // Maximum 7 days
    }

    function _validateParameters(
        uint256 targetRatio,
        uint256 spread,
        uint256 minSpread,
        uint256 maxOrderSize,
        uint256 slippageTolerance,
        uint256 minActiveOrders,
        uint256 rebalanceInterval
    ) internal view {
        Storage storage $ = getStorage();
        
        require(targetRatio >= $.minTargetRatio && targetRatio <= $.maxTargetRatio, "Invalid targetRatio");
        require(spread >= $.minSpread && spread <= $.maxSpread, "Invalid spread");
        require(minSpread >= $.minSpread, "minSpread too low");
        require(maxOrderSize >= $.minOrderSize && maxOrderSize <= $.maxOrderSize, "Invalid maxOrderSize");
        require(slippageTolerance >= $.minSlippageTolerance && slippageTolerance <= $.maxSlippageTolerance, "Invalid slippageTolerance");
        require(minActiveOrders >= $.minActiveOrders && minActiveOrders <= $.maxActiveOrders, "Invalid minActiveOrders");
        require(rebalanceInterval >= $.minRebalanceInterval && rebalanceInterval <= $.maxRebalanceInterval, "Invalid rebalanceInterval");
        require(spread >= minSpread, "spread must be >= minSpread");
    }
    
    function createVault(
        string memory name,
        string memory symbol,
        address base,
        address quote,
        uint256[7] memory params
    ) external returns (address vault) {
        Storage storage $ = getStorage();
        
        // Validate parameters
        _validateParameters(
            params[0], // targetRatio
            params[1], // spread
            params[2], // minSpread
            params[3], // maxOrderSize
            params[4], // slippageTolerance
            params[5], // minActiveOrders
            params[6]  // rebalanceInterval
        );
        
        bytes memory initData = abi.encodeWithSelector(
            GTXMarketMakerVault.initialize.selector,
            name,
            symbol,
            $.veToken,
            $.gaugeController,
            $.router,
            $.poolManager,
            $.balanceManager,
            base,
            quote,
            params[0], 
            params[1], 
            params[2], 
            params[3], 
            params[4], 
            params[5], 
            params[6], 
            msg.sender
        );
        
        BeaconProxy vaultProxy = new BeaconProxy($.vaultBeacon, initData);
        vault = address(vaultProxy);
        
        $.isVault[vault] = true;
        
        emit VaultCreated(vault, msg.sender, base, quote);
        
        return vault;
    }

    function createVaultWithRecommendedParams(
        string memory name,
        string memory symbol,
        address base,
        address quote
    ) external returns (address vault) {
        Storage storage $ = getStorage();
        
        // Use recommended middle values from allowed ranges
        uint256 targetRatio = ($.minTargetRatio + $.maxTargetRatio) / 2;    // 50%
        uint256 spread = $.minSpread * 4;                                   // 4x minimum spread
        uint256 minSpread = $.minSpread;                                    // Minimum allowed spread
        uint256 maxOrderSize = $.minOrderSize * 10;                         // 10x minimum size
        uint256 slippageTolerance = ($.minSlippageTolerance + $.maxSlippageTolerance) / 2;
        uint256 minActiveOrders = $.minActiveOrders * 2;                    // 2x minimum orders
        uint256 rebalanceInterval = 1 hours;                                // 1 hour interval
        
        // Create initialization data for the proxy
        bytes memory initData = abi.encodeWithSelector(
            GTXMarketMakerVault.initialize.selector,
            name,
            symbol,
            $.veToken,
            $.gaugeController,
            $.router,
            $.poolManager,
            $.balanceManager,
            base,
            quote,
            targetRatio,
            spread,
            minSpread,
            maxOrderSize,
            slippageTolerance,
            minActiveOrders,
            rebalanceInterval,
            msg.sender 
        );
        
        BeaconProxy vaultProxy = new BeaconProxy($.vaultBeacon, initData);
        vault = address(vaultProxy);
        
        $.isVault[vault] = true;
        
        emit VaultCreated(vault, msg.sender, base, quote);
        return vault;
    }
    
    function isValidVault(address _vault) external view returns (bool) {
        return getStorage().isVault[_vault];
    }
    
    function updateInfrastructure(
        address _router,
        address _poolManager,
        address _balanceManager
    ) external onlyOwner {
        require(_router != address(0), "Zero router");
        require(_poolManager != address(0), "Zero poolManager");
        require(_balanceManager != address(0), "Zero balanceManager");
        
        Storage storage $ = getStorage();
        $.router = _router;
        $.poolManager = _poolManager;
        $.balanceManager = _balanceManager;
        
        emit InfrastructureUpdated(_router, _poolManager, _balanceManager);
    }
    
    function updateGaugeAddresses(
        address _veToken,
        address _gaugeController
    ) external onlyOwner {
        require(_veToken != address(0), "Zero veToken");
        require(_gaugeController != address(0), "Zero gaugeController");
        
        Storage storage $ = getStorage();
        $.veToken = _veToken;
        $.gaugeController = _gaugeController;
    }

    function updateParameterConstraints(
        uint256 _minTargetRatio,
        uint256 _maxTargetRatio,
        uint256 _minSpread,
        uint256 _maxSpread,
        uint256 _minOrderSize,
        uint256 _maxOrderSize,
        uint256 _minSlippageTolerance,
        uint256 _maxSlippageTolerance,
        uint256 _minActiveOrders,
        uint256 _maxActiveOrders,
        uint256 _minRebalanceInterval,
        uint256 _maxRebalanceInterval
    ) external onlyOwner {
        require(_minTargetRatio < _maxTargetRatio, "Invalid target ratio range");
        require(_minSpread < _maxSpread, "Invalid spread range");
        require(_minOrderSize < _maxOrderSize, "Invalid order size range");
        require(_minSlippageTolerance < _maxSlippageTolerance, "Invalid slippage range");
        require(_minActiveOrders < _maxActiveOrders, "Invalid active orders range");
        require(_minRebalanceInterval < _maxRebalanceInterval, "Invalid interval range");
        
        Storage storage $ = getStorage();
        $.minTargetRatio = _minTargetRatio;
        $.maxTargetRatio = _maxTargetRatio;
        $.minSpread = _minSpread;
        $.maxSpread = _maxSpread;
        $.minOrderSize = _minOrderSize;
        $.maxOrderSize = _maxOrderSize;
        $.minSlippageTolerance = _minSlippageTolerance;
        $.maxSlippageTolerance = _maxSlippageTolerance;
        $.minActiveOrders = _minActiveOrders;
        $.maxActiveOrders = _maxActiveOrders;
        $.minRebalanceInterval = _minRebalanceInterval;
        $.maxRebalanceInterval = _maxRebalanceInterval;
        
        emit ParameterConstraintsUpdated();
    }
    
    function updateVaultImplementation(address _newImplementation) external onlyOwner {
        require(_newImplementation != address(0), "Zero implementation");
        require(_newImplementation.code.length > 0, "Not a contract");
        
        Storage storage $ = getStorage();
        address oldImpl = $.vaultImplementation;
        
        // Update the beacon with the new implementation
        UpgradeableBeacon($.vaultBeacon).upgradeTo(_newImplementation);
        $.vaultImplementation = _newImplementation;
        
        emit VaultImplementationUpdated(oldImpl, _newImplementation);
    }
    
    function getVaultImplementation() external view returns (address) {
        return getStorage().vaultImplementation;
    }
    
    function getVaultBeacon() external view returns (address) {
        return getStorage().vaultBeacon;
    }
    
    function getParameterConstraints() external view returns (
        uint256 minTargetRatio,
        uint256 maxTargetRatio,
        uint256 minSpread,
        uint256 maxSpread,
        uint256 minOrderSize,
        uint256 maxOrderSize,
        uint256 minSlippageTolerance,
        uint256 maxSlippageTolerance,
        uint256 minActiveOrders,
        uint256 maxActiveOrders,
        uint256 minRebalanceInterval,
        uint256 maxRebalanceInterval
    ) {
        Storage storage $ = getStorage();
        return (
            $.minTargetRatio,
            $.maxTargetRatio,
            $.minSpread,
            $.maxSpread,
            $.minOrderSize,
            $.maxOrderSize,
            $.minSlippageTolerance,
            $.maxSlippageTolerance,
            $.minActiveOrders,
            $.maxActiveOrders,
            $.minRebalanceInterval,
            $.maxRebalanceInterval
        );
    }

    function getInfrastructureAddresses() external view returns (
        address veTokenAddr,
        address gaugeControllerAddr,
        address routerAddr,
        address poolManagerAddr,
        address balanceManagerAddr
    ) {
        Storage storage $ = getStorage();
        return (
            $.veToken,
            $.gaugeController,
            $.router,
            $.poolManager,
            $.balanceManager
        );
    }
}