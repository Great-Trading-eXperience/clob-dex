// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

interface IGTXMarketMakerFactory {
    event VaultCreated(address vault, address creator, address base, address quote);
    event InfrastructureUpdated(address router, address poolManager, address balanceManager);
    event ParameterConstraintsUpdated();
    event VaultImplementationUpdated(address oldImpl, address newImpl);

    function initialize(
        address _owner,
        address _veToken,
        address _gaugeController,
        address _router,
        address _poolManager,
        address _balanceManager,
        address _vaultImplementation
    ) external;
    
    function createVault(
        string memory name,
        string memory symbol,
        address base,
        address quote,
        uint256[7] memory params
    ) external returns (address vault);

    function createVaultWithRecommendedParams(
        string memory name,
        string memory symbol,
        address base,
        address quote
    ) external returns (address vault);
    
    function isValidVault(address _vault) external view returns (bool);
    
    function updateInfrastructure(
        address _router,
        address _poolManager,
        address _balanceManager
    ) external;
    
    function updateGaugeAddresses(
        address _veToken,
        address _gaugeController
    ) external;

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
    ) external;
    
    function updateVaultImplementation(address _newImplementation) external;
    
    function getVaultImplementation() external view returns (address);
    
    function getVaultBeacon() external view returns (address);
    
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
    );

    function getInfrastructureAddresses() external view returns (
        address veTokenAddr,
        address gaugeControllerAddr,
        address routerAddr,
        address poolManagerAddr,
        address balanceManagerAddr
    );
}