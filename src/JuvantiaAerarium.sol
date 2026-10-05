// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {JuvantiaPaymentRegistry} from "./JuvantiaPaymentRegistry.sol";

interface IBudgetSettlement {
    function claimAccountFor(address account) external returns (uint256);
    function pay(bytes32 categoryId, bytes32 paymentId, uint256 gross, uint8 kind, address destination)
        external
        returns (uint256);
}

/// @notice Central Treasury and Tax Register for the Juvantia ecosystem.
contract JuvantiaAerarium is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable revenueToken;
    uint256 public totalCollected;
    uint256 public totalSpent;

    JuvantiaPaymentRegistry public paymentRegistry;
    address public revenueDistributor;

    event TaxReceived(address indexed source, uint256 amount, bytes32 indexed categoryId);
    event TreasurySpent(address indexed recipient, uint256 amount, string purpose);
    event SettlementConfigured(address indexed registry, address indexed distributor);

    constructor(address token, address admin) Ownable(admin) {
        require(token.code.length > 0, "Invalid token");
        require(admin != address(0), "Invalid admin");
        revenueToken = IERC20(token);
    }

    function configureSettlement(address registry, address distributor) external onlyOwner {
        require(revenueDistributor == address(0), "Already configured");
        require(registry.code.length > 0 && distributor.code.length > 0, "Invalid configuration");
        paymentRegistry = JuvantiaPaymentRegistry(registry);
        revenueDistributor = distributor;
        emit SettlementConfigured(registry, distributor);
    }

    function getTaxRateBps(bytes32 categoryId) external view returns (uint256) {
        return paymentRegistry.currentRule(categoryId).taxBps;
    }

    // A budget expense may return its tax to this contract while spend holds the guard.
    // Only the guarded Distributor can collect tax; the budget cannot initiate another payment here.
    function receiveTax(uint256 amount, bytes32 categoryId) external {
        require(msg.sender == revenueDistributor, "Only distributor");
        require(amount > 0, "Zero amount");
        uint256 beforeBalance = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        require(revenueToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");
        totalCollected += amount;
        emit TaxReceived(msg.sender, amount, categoryId);
    }

    function spend(address recipient, uint256 amount, string calldata purpose) external onlyOwner nonReentrant {
        _spend(recipient, amount, purpose);
    }

    function spendReviewed(address recipient, uint256 amount, string calldata purpose, uint256 expectedRevision)
        external
        onlyOwner
        nonReentrant
    {
        require(paymentRegistry.currentRevision(keccak256("BUDGET_EXPENSE")) == expectedRevision, "Rule changed");
        _spend(recipient, amount, purpose);
    }

    function _spend(address recipient, uint256 amount, string calldata purpose) internal {
        require(recipient != address(0) && amount > 0, "Invalid payment");
        require(bytes(purpose).length > 0, "Empty purpose");
        IBudgetSettlement(revenueDistributor).claimAccountFor(address(this));
        totalSpent += amount;
        revenueToken.forceApprove(revenueDistributor, amount);
        IBudgetSettlement(revenueDistributor)
            .pay(
                keccak256("BUDGET_EXPENSE"), keccak256(abi.encode(totalSpent, recipient, purpose)), amount, 0, recipient
            );
        emit TreasurySpent(recipient, amount, purpose);
    }
}
