// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Payment receipts for service requests. Business quotes and entitlements are checked by Core.
contract JuvantiaServicePayments is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable paymentToken;
    mapping(address => mapping(bytes32 => bool)) public paid;

    event ServicePaid(bytes32 indexed requestId, address indexed payer, address indexed recipient, uint256 amount);

    constructor(address token) {
        require(token.code.length > 0, "Invalid token");
        paymentToken = IERC20(token);
    }

    function pay(bytes32 requestId, address recipient, uint256 amount) external nonReentrant {
        require(requestId != bytes32(0) && recipient != address(0) && amount > 0, "Invalid payment");
        require(!paid[msg.sender][requestId], "Already paid");
        paid[msg.sender][requestId] = true;
        uint256 beforeBalance = paymentToken.balanceOf(recipient);
        paymentToken.safeTransferFrom(msg.sender, recipient, amount);
        require(paymentToken.balanceOf(recipient) - beforeBalance == amount, "Incorrect payment");
        emit ServicePaid(requestId, msg.sender, recipient, amount);
    }
}
