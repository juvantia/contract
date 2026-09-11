// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {JuvantiaAsset} from "./JuvantiaAsset.sol";
import {JuvantiaRevenueDistributor} from "./JuvantiaRevenueDistributor.sol";

contract JuvantiaAssetFabrica is UUPSUpgradeable, OwnableUpgradeable {
    address public immutable assetImplementation;
    JuvantiaRevenueDistributor public revenueDistributor;
    mapping(bytes32 => address) public assetById;
    address[] public assets;

    event AssetCreated(bytes32 indexed assetId, address indexed tokenAddress, address indexed initialOwner, string name);

    constructor(address implementation) {
        require(implementation.code.length > 0, "Invalid implementation");
        _disableInitializers();
        assetImplementation = implementation;
    }

    function initialize(address admin, address distributor) external initializer {
        require(distributor.code.length > 0, "Invalid distributor");
        __Ownable_init(admin);
        revenueDistributor = JuvantiaRevenueDistributor(distributor);
    }

    function createAsset(bytes32 assetId, string calldata name, address initialOwner)
        external onlyOwner returns (address clone)
    {
        require(assetId != bytes32(0) && assetById[assetId] == address(0), "Invalid or duplicate asset ID");
        clone = Clones.cloneDeterministic(assetImplementation, assetId);
        JuvantiaAsset(clone).initialize(name, "APU", initialOwner, owner(), address(revenueDistributor));
        revenueDistributor.registerAsset(clone);
        assetById[assetId] = clone;
        assets.push(clone);
        emit AssetCreated(assetId, clone, initialOwner, name);
    }

    function assetCount() external view returns (uint256) { return assets.length; }
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
