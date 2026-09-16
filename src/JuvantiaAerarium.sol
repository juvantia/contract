// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Central Treasury and Tax Register for the Juvantia ecosystem.
contract JuvantiaAerarium is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable revenueToken;
    uint256 public totalCollected;
    uint256 public totalSpent;

    // Per-category tax rate catalog (basis points, where 10_000 = 100%)
    mapping(bytes32 categoryId => uint256) public taxRateBps;

    event TaxReceived(address indexed source, uint256 amount, bytes32 indexed categoryId);
    event TreasurySpent(address indexed recipient, uint256 amount, string purpose);
    event TaxRateSet(bytes32 indexed categoryId, uint256 newRateBps);

    constructor(address token, address admin) Ownable(admin) {
        require(token.code.length > 0, "Invalid token");
        require(admin != address(0), "Invalid admin");
        revenueToken = IERC20(token);
    }

    function setTaxRate(bytes32 categoryId, uint256 newRateBps) external onlyOwner {
        require(categoryId != bytes32(0), "Invalid category");
        require(newRateBps <= 10_000, "Invalid tax rate");
        taxRateBps[categoryId] = newRateBps;
        emit TaxRateSet(categoryId, newRateBps);
    }

    function getTaxRateBps(bytes32 categoryId) external view returns (uint256) {
        return taxRateBps[categoryId];
    }

    function receiveTax(uint256 amount, bytes32 categoryId) external nonReentrant {
        require(amount > 0, "Zero amount");
        uint256 beforeBalance = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        require(revenueToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");
        totalCollected += amount;
        emit TaxReceived(msg.sender, amount, categoryId);
    }

    function spend(address recipient, uint256 amount, string calldata purpose) external onlyOwner nonReentrant {
        require(recipient != address(0) && amount > 0, "Invalid payment");
        require(bytes(purpose).length > 0, "Empty purpose");
        totalSpent += amount;
        revenueToken.safeTransfer(recipient, amount);
        emit TreasurySpent(recipient, amount, purpose);
    }
}
