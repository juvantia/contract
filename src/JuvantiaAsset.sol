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

    constructor() { _disableInitializers(); }

    function initialize(
        string memory name_, string memory symbol_, address initialOwner,
        address admin, address distributor
    ) external initializer {
        require(initialOwner != address(0) && distributor.code.length > 0, "Invalid initialization");
        __ERC20_init(name_, symbol_);
        __Ownable_init(admin);
        // The factory registers this clone immediately after initialization.
        _mint(initialOwner, FIXED_SUPPLY);
        revenueDistributor = distributor;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (revenueDistributor != address(0)) {
            IRevenueCheckpoint(revenueDistributor).checkpointTransfer(from, to);
        }
        super._update(from, to, amount);
    }
}
