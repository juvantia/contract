// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {JuvantiaRevenueDistributor} from "./JuvantiaRevenueDistributor.sol";
import {PaymentSettlement} from "./PaymentSettlement.sol";

/// @notice Thin invoice adapter. Approvals and all money custody belong to Distributor.
contract JuvantiaServicePayments is ReentrancyGuard {
    JuvantiaRevenueDistributor public immutable revenueDistributor;
    address public immutable paymentToken;
    mapping(address => mapping(bytes32 => bool)) public paid;

    event ServicePaid(bytes32 indexed requestId, address indexed payer, address indexed recipient, uint256 amount);

    constructor(address distributor) {
        require(distributor.code.length > 0, "Invalid distributor");
        revenueDistributor = JuvantiaRevenueDistributor(distributor);
        paymentToken = address(revenueDistributor.revenueToken());
    }

    function pay(PaymentSettlement.Invoice calldata invoice, bytes calldata signature) external nonReentrant {
        bytes32 requestId = invoice.payment.paymentId;
        require(!paid[msg.sender][requestId], "Already paid");
        paid[msg.sender][requestId] = true;
        revenueDistributor.payInvoiceFor(invoice, signature, msg.sender);
        emit ServicePaid(requestId, msg.sender, invoice.payment.destination, invoice.payment.gross);
    }
}
