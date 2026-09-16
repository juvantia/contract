// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {JuvantiaAerarium} from "./JuvantiaAerarium.sol";
import {JuvantiaRevenueDistributor} from "./JuvantiaRevenueDistributor.sol";

/// @notice Atomically routes lease tax to the central treasury and net revenue to asset holders.
contract JuvantiaLeasingHub is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable paymentToken;
    JuvantiaAerarium public immutable aerarium;
    JuvantiaRevenueDistributor public immutable distributor;

    bytes32 public constant LEASING_CATEGORY = keccak256("LEASING");
    mapping(address => mapping(bytes32 => bool)) public paid;

    event LeasePaid(bytes32 indexed leaseId, address indexed payer, address indexed asset, uint256 amount, uint256 tax, uint256 net);

    constructor(address token, address treasury, address revenue, address admin) Ownable(admin) {
        require(token.code.length > 0, "Invalid configuration");
        require(address(JuvantiaAerarium(treasury).revenueToken()) == token, "Treasury token mismatch");
        require(address(JuvantiaRevenueDistributor(revenue).revenueToken()) == token, "Revenue token mismatch");
        paymentToken = IERC20(token);
        aerarium = JuvantiaAerarium(treasury);
        distributor = JuvantiaRevenueDistributor(revenue);
    }

    function processLeasePayment(address asset, uint256 amount, bytes32 leaseId) external nonReentrant {
        require(distributor.registeredAssets(asset), "Unknown asset");
        require(leaseId != bytes32(0) && amount > 0, "Invalid lease");
        require(!paid[msg.sender][leaseId], "Already paid");
        paid[msg.sender][leaseId] = true;

        uint256 beforeBalance = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        require(paymentToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");

        uint256 taxRate = aerarium.getTaxRateBps(LEASING_CATEGORY);
        uint256 tax = Math.mulDiv(amount, taxRate, 10_000);
        uint256 net = amount - tax;

        if (tax > 0) {
            paymentToken.forceApprove(address(aerarium), tax);
            aerarium.receiveTax(tax, LEASING_CATEGORY);
        }
        if (net > 0) {
            paymentToken.forceApprove(address(distributor), net);
            distributor.distributeRevenue(asset, net);
        }
        emit LeasePaid(leaseId, msg.sender, asset, amount, tax, net);
    }
}
