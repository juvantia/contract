// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Immutable protocol code; only the owner publishes versioned financial data.
contract JuvantiaPaymentRegistry is Ownable {
    uint256 public constant MAX_QUOTE_TTL = 7 days;

    struct Rule {
        bool active;
        bool publicAccess;
        uint8 destinations; // bits: account=1, asset pool=2, addressed trade=4
        uint16 taxBps;
        uint16 commissionBps;
        uint256 fixedCommission;
        uint256 servicePrice; // optional fixed civic price; distinct from commission
        address commissionRecipient;
        uint256 sourceRoles; // TradeHub=1, ServicePayments=2, Consortium=4, Syndicate=8, Aerarium=16
    }

    struct Version {
        Rule rule;
        uint64 publishedAt;
        uint64 supersededAt;
    }

    mapping(bytes32 => uint256) public currentRevision;
    mapping(bytes32 => mapping(uint256 => Version)) private versions;
    mapping(address => bool) public invoiceIssuers;

    event RulePublished(bytes32 indexed categoryId, uint256 indexed revision, bytes32 ruleHash);
    event InvoiceIssuerSet(address indexed issuer, bool allowed);

    constructor(address admin) Ownable(admin) {}

    function publish(bytes32 categoryId, Rule calldata rule) external onlyOwner returns (uint256 revision) {
        require(categoryId != bytes32(0), "Invalid category");
        require(rule.destinations > 0 && rule.destinations <= 7, "Invalid destinations");
        require(uint256(rule.taxBps) + rule.commissionBps <= 10_000, "Invalid rates");
        require(rule.publicAccess || rule.sourceRoles != 0, "Missing source policy");
        require(!rule.publicAccess || rule.destinations & 4 == 0, "Private trade route");
        require(
            (rule.commissionBps == 0 && rule.fixedCommission == 0) || rule.commissionRecipient != address(0),
            "Missing commission recipient"
        );
        revision = currentRevision[categoryId] + 1;
        if (revision > 1) versions[categoryId][revision - 1].supersededAt = uint64(block.timestamp);
        versions[categoryId][revision] = Version(rule, uint64(block.timestamp), 0);
        currentRevision[categoryId] = revision;
        emit RulePublished(categoryId, revision, keccak256(abi.encode(rule)));
    }

    function setInvoiceIssuer(address issuer, bool allowed) external onlyOwner {
        require(issuer != address(0), "Invalid issuer");
        invoiceIssuers[issuer] = allowed;
        emit InvoiceIssuerSet(issuer, allowed);
    }

    function getVersion(bytes32 categoryId, uint256 revision) external view returns (Version memory version) {
        require(revision != 0 && revision <= currentRevision[categoryId], "Unknown rule");
        return versions[categoryId][revision];
    }

    function currentRule(bytes32 categoryId) public view returns (Rule memory) {
        uint256 revision = currentRevision[categoryId];
        require(revision != 0, "Unknown rule");
        Rule memory rule = versions[categoryId][revision].rule;
        require(rule.active, "Inactive rule");
        return rule;
    }

    /// @notice Historical versions are usable only by authenticated invoices or frozen system objects.
    function quotedRule(bytes32 categoryId, uint256 revision, uint256 issuedAt, uint256 expiresAt)
        external
        view
        returns (Rule memory)
    {
        require(revision != 0 && revision <= currentRevision[categoryId], "Unknown rule");
        Version memory version = versions[categoryId][revision];
        require(version.rule.active, "Inactive rule");
        require(issuedAt >= version.publishedAt && issuedAt <= block.timestamp, "Invalid quote time");
        require(version.supersededAt == 0 || issuedAt < version.supersededAt, "Stale quote");
        require(expiresAt > issuedAt && expiresAt <= issuedAt + MAX_QUOTE_TTL, "Invalid quote expiry");
        require(block.timestamp <= expiresAt, "Quote expired");
        return version.rule;
    }

    function calculate(Rule memory rule, uint256 gross)
        public
        pure
        returns (uint256 tax, uint256 commission, uint256 net)
    {
        require(gross > 0, "Invalid payment");
        tax = Math.mulDiv(gross, rule.taxBps, 10_000);
        commission = Math.mulDiv(gross, rule.commissionBps, 10_000) + rule.fixedCommission;
        require(tax + commission <= gross, "Insufficient gross");
        net = gross - tax - commission;
    }
}
