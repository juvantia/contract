// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract JuvantiaAerarium is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable revenueToken;
    uint256 public totalCollected;
    uint256 public totalSpent;

    event TaxReceived(address indexed source, uint256 amount, string category);
    event TreasurySpent(address indexed recipient, uint256 amount, string purpose);

    constructor(address token, address admin) Ownable(admin) {
        require(token.code.length > 0, "Invalid token");
        revenueToken = IERC20(token);
    }

    function receiveTax(uint256 amount, string calldata category) external nonReentrant {
        require(amount > 0, "Zero amount");
        uint256 beforeBalance = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        require(revenueToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");
        totalCollected += amount;
        emit TaxReceived(msg.sender, amount, category);
    }

    function spend(address recipient, uint256 amount, string calldata purpose) external onlyOwner nonReentrant {
        require(recipient != address(0) && amount > 0, "Invalid payment");
        totalSpent += amount;
        revenueToken.safeTransfer(recipient, amount);
        emit TreasurySpent(recipient, amount, purpose);
    }
}
