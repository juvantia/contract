// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {JuvantiaPaymentRegistry} from "./JuvantiaPaymentRegistry.sol";
import {JuvantiaAerarium} from "./JuvantiaAerarium.sol";

/// @dev Shared settlement and addressed custody. Asset accrual remains in RevenueDistributor.
abstract contract PaymentSettlement is Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    struct Payment {
        bytes32 paymentId;
        bytes32 categoryId;
        uint256 revision; // 0 selects the current revision
        uint8 kind;
        address destination;
        address asset; // only addressed trade needs a second asset identifier
        uint256 gross;
        uint256 issuedAt;
        uint256 expiresAt;
    }

    struct Invoice {
        Payment payment;
        address payer;
        address source;
    }

    bytes32 public constant INVOICE_TYPEHASH = keccak256(
        "Invoice(bytes32 paymentId,bytes32 categoryId,uint256 revision,uint8 kind,address destination,address asset,uint256 gross,uint256 issuedAt,uint256 expiresAt,address payer,address source)"
    );
    IERC20 public immutable revenueToken;
    JuvantiaAerarium public aerarium;
    JuvantiaPaymentRegistry public paymentRegistry;
    mapping(address => uint256) public sourceRoles;
    mapping(address => uint256) public registrarRoles;
    mapping(address => mapping(bytes32 => bool)) public paid;
    mapping(address => uint256) public accountRevenue;
    mapping(address => bool) public encumbered;

    event PaymentRegistrySet(address indexed registry);
    event PaymentSourceSet(address indexed source, uint256 roles);
    event AerariumSet(address indexed aerarium);
    event AccountRevenueClaimed(address indexed account, uint256 amount);
    event Settlement(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed destination,
        address source,
        bytes32 categoryId,
        uint256 revision,
        uint8 kind,
        address asset,
        uint256 gross,
        uint256 tax,
        uint256 commission,
        uint256 net
    );
    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed assetToken,
        bytes32 categoryId,
        uint256 amount,
        uint256 tax,
        uint256 net
    );

    constructor(address token, address admin, address treasury)
        Ownable(admin)
        EIP712("JuvantiaRevenueDistributor", "1")
    {
        require(token.code.length > 0, "Invalid token");
        revenueToken = IERC20(token);
        _setAerarium(treasury);
    }

    function setPaymentRegistry(address registry) external onlyOwner {
        require(address(paymentRegistry) == address(0) && registry.code.length > 0, "Invalid registry");
        paymentRegistry = JuvantiaPaymentRegistry(registry);
        emit PaymentRegistrySet(registry);
    }

    function setAerarium(address treasury) external onlyOwner {
        _setAerarium(treasury);
    }

    function _setAerarium(address treasury) internal {
        require(treasury.code.length > 0, "Invalid treasury");
        require(address(JuvantiaAerarium(treasury).revenueToken()) == address(revenueToken), "Treasury token mismatch");
        aerarium = JuvantiaAerarium(treasury);
        emit AerariumSet(treasury);
    }

    function setPaymentSource(address source, uint256 roles) external onlyOwner {
        _setSource(source, roles);
    }

    function setPaymentRegistrar(address registrar, uint256 roles) external onlyOwner {
        require(registrar.code.length > 0 && roles & ~uint256(12) == 0, "Invalid registrar roles");
        registrarRoles[registrar] = roles;
    }

    function registerPaymentSource(address source, uint256 roles) external {
        require(roles != 0 && registrarRoles[msg.sender] & roles == roles, "Not payment registrar");
        _setSource(source, roles);
    }

    function _setSource(address source, uint256 roles) internal {
        require(source.code.length > 0 && roles <= 31, "Invalid source");
        sourceRoles[source] = roles;
        emit PaymentSourceSet(source, roles);
    }

    function pay(bytes32 categoryId, bytes32 paymentId, uint256 gross, uint8 kind, address destination)
        external
        nonReentrant
        returns (uint256 net)
    {
        return _settle(Payment(paymentId, categoryId, 0, kind, destination, address(0), gross, 0, 0), msg.sender);
    }

    /// @dev Only configured modules may pull from their authenticated caller/order buyer.
    function payFor(Payment calldata payment, address payer) external nonReentrant returns (uint256 net) {
        require(sourceRoles[msg.sender] != 0, "Not payment source");
        return _settle(payment, payer);
    }

    function payInvoice(Invoice calldata invoice, bytes calldata signature) external nonReentrant returns (uint256) {
        require(invoice.payer == msg.sender && invoice.source == address(0), "Invoice payer mismatch");
        _verifyInvoice(invoice, signature);
        return _settle(invoice.payment, msg.sender);
    }

    function payInvoiceFor(Invoice calldata invoice, bytes calldata signature, address payer)
        external
        nonReentrant
        returns (uint256)
    {
        require(sourceRoles[msg.sender] != 0, "Not payment source");
        require(invoice.payer == payer && invoice.source == msg.sender, "Invoice payer mismatch");
        _verifyInvoice(invoice, signature);
        return _settle(invoice.payment, payer);
    }

    function hashInvoice(Invoice calldata invoice) public view returns (bytes32) {
        Payment calldata p = invoice.payment;
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    INVOICE_TYPEHASH,
                    p.paymentId,
                    p.categoryId,
                    p.revision,
                    p.kind,
                    p.destination,
                    p.asset,
                    p.gross,
                    p.issuedAt,
                    p.expiresAt,
                    invoice.payer,
                    invoice.source
                )
            )
        );
    }

    function _verifyInvoice(Invoice calldata invoice, bytes calldata signature) internal view {
        require(invoice.payment.revision != 0, "Missing invoice revision");
        require(
            paymentRegistry.invoiceIssuers(ECDSA.recover(hashInvoice(invoice), signature)), "Invalid invoice signature"
        );
    }

    function _settle(Payment memory p, address payer) internal returns (uint256 net) {
        require(address(paymentRegistry) != address(0), "Registry unavailable");
        require(payer != address(0) && p.paymentId != bytes32(0) && p.gross > 0, "Invalid payment");
        require(!paid[payer][p.paymentId], "Already paid");
        require(p.kind <= 2 && p.destination != address(0) && p.destination != address(this), "Invalid destination");
        JuvantiaPaymentRegistry.Rule memory rule = p.revision == 0
            ? paymentRegistry.currentRule(p.categoryId)
            : paymentRegistry.quotedRule(p.categoryId, p.revision, p.issuedAt, p.expiresAt);
        require(rule.publicAccess || rule.sourceRoles & sourceRoles[msg.sender] != 0, "Restricted category");
        require(rule.destinations & (1 << p.kind) != 0, "Invalid destination kind");
        require(rule.servicePrice == 0 || p.gross == rule.servicePrice, "Incorrect service price");
        // Raw calls cannot choose a historical rate, even for public commercial categories.
        require(p.revision == 0 || sourceRoles[msg.sender] != 0 || p.issuedAt != 0, "Invalid revision");
        if (p.revision == 0) p.revision = paymentRegistry.currentRevision(p.categoryId);
        (uint256 tax, uint256 commission, uint256 remainder_) = paymentRegistry.calculate(rule, p.gross);
        net = remainder_;
        _validateCredit(p);
        paid[payer][p.paymentId] = true;
        uint256 beforeBalance = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(payer, address(this), p.gross);
        require(revenueToken.balanceOf(address(this)) - beforeBalance == p.gross, "Incorrect deposit");
        if (tax != 0) {
            revenueToken.forceApprove(address(aerarium), tax);
            aerarium.receiveTax(tax, p.categoryId);
        }
        if (commission != 0) accountRevenue[rule.commissionRecipient] += commission;
        if (net != 0) _credit(p, net);
        _emitSettlement(p, payer, tax, commission, net);
    }

    function _emitSettlement(Payment memory p, address payer, uint256 tax, uint256 commission, uint256 net) private {
        emit Settlement(
            p.paymentId,
            payer,
            p.destination,
            msg.sender,
            p.categoryId,
            p.revision,
            p.kind,
            p.asset,
            p.gross,
            tax,
            commission,
            net
        );
        if (p.kind == 1) emit PaymentProcessed(p.paymentId, payer, p.destination, p.categoryId, p.gross, tax, net);
    }

    function _validateCredit(Payment memory payment) internal view virtual;
    function _credit(Payment memory payment, uint256 net) internal virtual;

    function claimAccount() external nonReentrant returns (uint256) {
        return _claimAccount(msg.sender);
    }

    function claimAccountFor(address account) external nonReentrant returns (uint256) {
        return _claimAccount(account);
    }

    function _claimAccount(address account) internal returns (uint256 amount) {
        require(account != address(0), "Invalid account");
        require(!encumbered[account], "Account encumbered");
        amount = accountRevenue[account];
        if (amount != 0) {
            accountRevenue[account] = 0;
            revenueToken.safeTransfer(account, amount);
            emit AccountRevenueClaimed(account, amount);
        }
    }
}
