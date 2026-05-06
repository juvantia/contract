// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract JuvantiaAsset is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address initialOwner,
        address admin
    ) initializer public {
        __ERC20_init(name, symbol);
        __Ownable_init(admin);
        
        // Mint exactly 100,000 shares with 18 decimals upon clone creation
        _mint(initialOwner, 100_000 * 10 ** decimals());
    }

    // Optional admin minting for future token splits or structural changes
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // Admin function to burn tokens from a specific address
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}