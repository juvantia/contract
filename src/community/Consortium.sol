// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConsortiumTreasury} from "./ConsortiumTreasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Governed commercial entity implementation for Juvantia Consortia.
contract Consortium is ConsortiumTreasury {
    using SafeERC20 for IERC20;

    enum ProposalType {
        MagisterElection,
        SpendingLimitsPackage,
        RevenueDistribution,
        TreasurySale,
        MajorExpenditure
    }

    struct Proposal {
        ProposalType pType;
        address proposer;
        uint256 openedAt;
        uint256 deadline;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bytes data;
    }

    address public magister;
    address public admin;
    address public tribunal;
    uint256 public pettyLimit;
    uint256 public majorLimit;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event MagisterChanged(address indexed newMagister);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event TribunalSet(address indexed oldTribunal, address indexed newTribunal);
    event JudicialPaymentSeized(address indexed recipient, uint256 amount);
    event JudicialSharesSeized(address indexed recipient, uint256 amount);
    event JudicialTokenSeized(address indexed token, address indexed recipient, uint256 amount);
    event SpendingLimitsChanged(uint256 petty, uint256 major);
    event ProposalCreated(uint256 indexed proposalId, ProposalType indexed pType, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, ProposalType indexed pType);
    event TreasuryTopUp(address indexed contributor, uint256 amount);
    event TreasurySharesSold(address indexed buyer, uint256 sharesAmount, uint256 totalEUR);

    modifier onlyMagister() {
        require(msg.sender == magister, "Only magister");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyTribunal() {
        require(msg.sender == tribunal && tribunal != address(0), "Only tribunal");
        _;
    }

    function initialize(address token, address shares, address distributor, address initialMagister, address admin_)
        external
        initializer
    {
        _initialize(token, shares, distributor, initialMagister, admin_, address(0));
    }

    function initialize(
        address token,
        address shares,
        address distributor,
        address initialMagister,
        address admin_,
        address initialTribunal
    ) external initializer {
        _initialize(token, shares, distributor, initialMagister, admin_, initialTribunal);
    }

    function _initialize(
        address token,
        address shares,
        address distributor,
        address initialMagister,
        address admin_,
        address initialTribunal
    ) internal onlyInitializing {
        require(initialMagister != address(0), "Invalid magister");
        require(admin_ != address(0), "Invalid admin");
        _initializeTreasury(token, shares, distributor);
        magister = initialMagister;
        admin = admin_;
        tribunal = initialTribunal;
        pettyLimit = 1_000 ether;
        majorLimit = 50_000 ether;
    }

    function setTribunal(address newTribunal) external onlyAdmin {
        address old = tribunal;
        tribunal = newTribunal;
        emit TribunalSet(old, newTribunal);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin");
        address old = admin;
        admin = newAdmin;
        emit AdminChanged(old, newAdmin);
    }

    /// @notice Judicial seizure of EURO payment tokens by the Tribunal.
    function judicialSeizePayment(address to, uint256 amount) external onlyTribunal nonReentrant {
        require(to != address(0) && to != address(this), "Invalid recipient");
        require(amount > 0, "Zero amount");
        uint256 totalBal = paymentToken.balanceOf(address(this));
        require(amount <= totalBal, "Insufficient balance");

        uint256 opBal = operatingBalance();
        if (amount > opBal) {
            uint256 excess = amount - opBal;
            distributablePool -= excess;
        }

        paymentToken.safeTransfer(to, amount);
        emit JudicialPaymentSeized(to, amount);
    }

    /// @notice Judicial seizure of Consortium APU treasury shares by the Tribunal.
    function judicialSeizeShares(address to, uint256 amount) external onlyTribunal nonReentrant {
        require(to != address(0) && to != address(this), "Invalid recipient");
        require(amount > 0, "Zero amount");
        require(treasuryShares() >= amount, "Insufficient treasury shares");

        shareToken.safeTransfer(to, amount);
        emit JudicialSharesSeized(to, amount);
    }

    /// @notice Judicial seizure of any ERC-20 token (paymentToken, shares, or external APU token) by the Tribunal.
    function judicialSeizeToken(address token, address to, uint256 amount) external onlyTribunal nonReentrant {
        require(token != address(0), "Invalid token");
        require(to != address(0) && to != address(this), "Invalid recipient");
        require(amount > 0, "Zero amount");

        if (token == address(paymentToken)) {
            uint256 totalBal = paymentToken.balanceOf(address(this));
            require(amount <= totalBal, "Insufficient balance");
            uint256 opBal = operatingBalance();
            if (amount > opBal) {
                uint256 excess = amount - opBal;
                distributablePool -= excess;
            }
            paymentToken.safeTransfer(to, amount);
            emit JudicialPaymentSeized(to, amount);
        } else if (token == address(shareToken)) {
            require(treasuryShares() >= amount, "Insufficient treasury shares");
            shareToken.safeTransfer(to, amount);
            emit JudicialSharesSeized(to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
            emit JudicialTokenSeized(token, to, amount);
        }
    }

    /// @notice Magister can execute operational expenditure within petty limit directly.
    function spendOperating(address recipient, uint256 amount, bytes32 referenceId) external onlyMagister nonReentrant {
        require(amount <= pettyLimit, "Exceeds petty limit");
        _spendOperating(recipient, amount, referenceId);
    }

    /// @notice Magister claims device revenue from RevenueDistributor into operating balance.
    function claimDeviceRevenue(address assetToken) external onlyMagister nonReentrant returns (uint256) {
        return _claimDeviceRevenue(assetToken);
    }

    /// @notice Shareholders can contribute shares to treasury.
    function contributeSharesToTreasury(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");
        shareToken.safeTransferFrom(msg.sender, address(this), amount);
        emit TreasuryTopUp(msg.sender, amount);
    }

    /// @notice Propose a governance action. Proposer must hold >= 1% of circulating voting shares.
    function propose(ProposalType pType, bytes calldata data) external returns (uint256 proposalId) {
        uint256 supply = circulatingSupply();
        require(supply > 0, "No circulating shares");
        require(shareToken.balanceOf(msg.sender) >= supply / 100, "Must hold >= 1% circulating shares");

        proposalId = ++proposalCount;
        proposals[proposalId] = Proposal({
            pType: pType,
            proposer: msg.sender,
            openedAt: block.timestamp,
            deadline: block.timestamp + 36 hours,
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            data: data
        });

        emit ProposalCreated(proposalId, pType, msg.sender);
    }

    /// @notice Cast a vote on an active proposal.
    function castVote(uint256 proposalId, bool support) external {
        Proposal storage prop = proposals[proposalId];
        require(prop.openedAt != 0, "Proposal not found");
        require(block.timestamp <= prop.deadline, "Voting closed");
        require(!prop.executed, "Already executed");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        uint256 weight = shareToken.balanceOf(msg.sender);
        require(weight > 0, "No voting weight");
        require(msg.sender != address(this), "Treasury cannot vote");

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            prop.forVotes += weight;
        } else {
            prop.againstVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);

        if (_isThresholdMet(prop)) {
            _executeProposal(proposalId);
        }
    }

    /// @notice Manually execute an approved proposal.
    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage prop = proposals[proposalId];
        require(prop.openedAt != 0, "Proposal not found");
        require(block.timestamp <= prop.deadline, "Proposal expired");
        require(!prop.executed, "Already executed");
        require(_isThresholdMet(prop), "Threshold not met");

        _executeProposal(proposalId);
    }

    function _isThresholdMet(Proposal storage prop) internal view returns (bool) {
        uint256 supply = circulatingSupply();
        if (supply == 0) return false;

        if (
            prop.pType == ProposalType.MagisterElection || prop.pType == ProposalType.SpendingLimitsPackage
                || prop.pType == ProposalType.MajorExpenditure
        ) {
            return prop.forVotes > Math.mulDiv(supply, 50001, 100000); // > 50.001%
        } else if (prop.pType == ProposalType.RevenueDistribution || prop.pType == ProposalType.TreasurySale) {
            return prop.forVotes >= Math.mulDiv(supply, 75000, 100000); // >= 75.000%
        }
        return false;
    }

    function _executeProposal(uint256 proposalId) internal {
        Proposal storage prop = proposals[proposalId];
        prop.executed = true;

        if (prop.pType == ProposalType.MagisterElection) {
            address newMagister = abi.decode(prop.data, (address));
            require(newMagister != address(0), "Invalid magister");
            magister = newMagister;
            emit MagisterChanged(newMagister);
        } else if (prop.pType == ProposalType.SpendingLimitsPackage) {
            (uint256 p, uint256 m) = abi.decode(prop.data, (uint256, uint256));
            pettyLimit = p;
            majorLimit = m;
            emit SpendingLimitsChanged(p, m);
        } else if (prop.pType == ProposalType.MajorExpenditure) {
            (address recipient, uint256 amount, bytes32 referenceId) =
                abi.decode(prop.data, (address, uint256, bytes32));
            require(amount <= majorLimit, "Exceeds major limit");
            _spendOperating(recipient, amount, referenceId);
        } else if (prop.pType == ProposalType.RevenueDistribution) {
            uint256 amount = abi.decode(prop.data, (uint256));
            _allocateDistributable(amount);
        } else if (prop.pType == ProposalType.TreasurySale) {
            (address buyer, uint256 sharesAmount, uint256 totalEUR) = abi.decode(prop.data, (address, uint256, uint256));
            require(buyer != address(0), "Invalid buyer");
            require(treasuryShares() >= sharesAmount, "Insufficient treasury shares");
            paymentToken.safeTransferFrom(buyer, address(this), totalEUR);
            shareToken.safeTransfer(buyer, sharesAmount);
            emit TreasurySharesSold(buyer, sharesAmount, totalEUR);
        }

        emit ProposalExecuted(proposalId, prop.pType);
    }
}
