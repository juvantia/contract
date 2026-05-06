// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./JuvantiaAsset.sol";

contract JuvantiaAssetFabrica is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    
    address public immutable assetImplementation;

    event AssetCreated(address indexed tokenAddress, address indexed initialOwner, string name, string symbol);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _assetImplementation) {
        _disableInitializers();
        assetImplementation = _assetImplementation;
    }

    function initialize() initializer public {
        __Ownable_init(msg.sender);
    }

    function createAsset(string calldata name, string calldata symbol, address initialOwner) 
        external onlyOwner returns (address) 
    {
        // Deploying minimal proxy (EIP-1167)
        address clone = Clones.clone(assetImplementation);
        
        // Initializing the clone and transferring ownership to the backend
        JuvantiaAsset(clone).initialize(name, symbol, initialOwner, owner());
        
        emit AssetCreated(clone, initialOwner, name, symbol);
        return clone;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}