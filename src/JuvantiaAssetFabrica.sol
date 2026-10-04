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
    address public tribunal;
    mapping(bytes32 => address) public assetById;
    address[] public assets;
    mapping(address => address) public parentAsset;
    mapping(address => address[]) internal _subAssets;

    event AssetCreated(
        bytes32 indexed assetId, address indexed tokenAddress, address indexed initialOwner, string name
    );
    event SubAssetCreated(
        bytes32 indexed parentAssetId, bytes32 indexed assetId, address indexed tokenAddress, address parentTokenAddress
    );
    event TribunalSet(address indexed oldTribunal, address indexed newTribunal);

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

    function setTribunal(address newTribunal) external onlyOwner {
        address old = tribunal;
        tribunal = newTribunal;
        emit TribunalSet(old, newTribunal);
    }

    function createAsset(bytes32 assetId, string calldata name, address initialOwner)
        external
        onlyOwner
        returns (address clone)
    {
        return _createAsset(assetId, name, "APU", initialOwner);
    }

    function createAsset(bytes32 assetId, string calldata name, string calldata symbol, address initialOwner)
        external
        onlyOwner
        returns (address clone)
    {
        return _createAsset(assetId, name, symbol, initialOwner);
    }

    function _createAsset(bytes32 assetId, string memory name, string memory symbol, address initialOwner)
        internal
        returns (address clone)
    {
        require(assetId != bytes32(0) && assetById[assetId] == address(0), "Invalid or duplicate asset ID");
        clone = Clones.cloneDeterministic(assetImplementation, assetId);
        JuvantiaAsset(clone).initialize(name, symbol, initialOwner, owner(), address(revenueDistributor), tribunal);
        revenueDistributor.registerAsset(clone);
        assetById[assetId] = clone;
        assets.push(clone);
        emit AssetCreated(assetId, clone, initialOwner, name);
    }

    function createSubAsset(
        bytes32 parentAssetId,
        bytes32 assetId,
        string calldata name,
        string calldata symbol,
        address initialOwner
    ) external onlyOwner returns (address clone) {
        address parent = assetById[parentAssetId];
        require(parent != address(0), "Parent asset does not exist");

        clone = _createAsset(assetId, name, symbol, initialOwner);
        parentAsset[clone] = parent;
        _subAssets[parent].push(clone);

        emit SubAssetCreated(parentAssetId, assetId, clone, parent);
    }

    function subAssetCount(address parent) external view returns (uint256) {
        return _subAssets[parent].length;
    }

    function getSubAssets(address parent) external view returns (address[] memory) {
        return _subAssets[parent];
    }

    function assetCount() external view returns (uint256) {
        return assets.length;
    }
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
