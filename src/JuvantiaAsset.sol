// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IRevenueCheckpoint {
    function checkpointTransfer(address from, address to) external;
}

/// @notice Fixed-supply asset passport. Earned revenue stays with the earning holder.
contract JuvantiaAsset is ERC20Upgradeable, OwnableUpgradeable {
    uint256 public constant FIXED_SUPPLY = 100_000 ether;
    address public revenueDistributor;
    address public tribunal;

    event TribunalSet(address indexed oldTribunal, address indexed newTribunal);
    event JudicialTransfer(address indexed from, address indexed to, uint256 amount);

    modifier onlyTribunal() {
        require(msg.sender == tribunal && tribunal != address(0), "Only tribunal");
        _;
    }

    constructor() { _disableInitializers(); }

    function initialize(
        string memory name_, string memory symbol_, address initialOwner,
        address admin, address distributor
    ) external initializer {
        _initialize(name_, symbol_, initialOwner, admin, distributor, address(0));
    }

    function initialize(
        string memory name_, string memory symbol_, address initialOwner,
        address admin, address distributor, address initialTribunal
    ) external initializer {
        _initialize(name_, symbol_, initialOwner, admin, distributor, initialTribunal);
    }

    function _initialize(
        string memory name_, string memory symbol_, address initialOwner,
        address admin, address distributor, address initialTribunal
    ) internal onlyInitializing {
        require(initialOwner != address(0) && distributor.code.length > 0, "Invalid initialization");
        __ERC20_init(name_, symbol_);
        __Ownable_init(admin);
        // The factory registers this clone immediately after initialization.
        _mint(initialOwner, FIXED_SUPPLY);
        revenueDistributor = distributor;
        tribunal = initialTribunal;
    }

    function setTribunal(address newTribunal) external onlyOwner {
        address old = tribunal;
        tribunal = newTribunal;
        emit TribunalSet(old, newTribunal);
    }

    /// @notice Seize APU shares from an account by judicial decree.
    function judicialTransfer(address from, address to, uint256 amount) external onlyTribunal {
        require(from != address(0), "Invalid from");
        require(to != address(0) && to != address(this), "Invalid to");
        require(amount > 0, "Zero amount");
        _transfer(from, to, amount);
        emit JudicialTransfer(from, to, amount);
    }

    /// @notice Alias for judicialTransfer.
    function judicialSeize(address from, address to, uint256 amount) external onlyTribunal {
        require(from != address(0), "Invalid from");
        require(to != address(0) && to != address(this), "Invalid to");
        require(amount > 0, "Zero amount");
        _transfer(from, to, amount);
        emit JudicialTransfer(from, to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (revenueDistributor != address(0)) {
            IRevenueCheckpoint(revenueDistributor).checkpointTransfer(from, to);
        }
        super._update(from, to, amount);
    }
}
