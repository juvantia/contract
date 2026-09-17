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
        TreasurySale
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
    uint256 public pettyLimit;
    uint256 public standardLimit;
    uint256 public majorLimit;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event MagisterChanged(address indexed newMagister);
    event SpendingLimitsChanged(uint256 petty, uint256 standard, uint256 major);
    event ProposalCreated(uint256 indexed proposalId, ProposalType indexed pType, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId, ProposalType indexed pType);
    event TreasuryTopUp(address indexed contributor, uint256 amount);
    event TreasurySharesSold(address indexed buyer, uint256 sharesAmount, uint256 totalEUR);

    modifier onlyMagister() {
        require(msg.sender == magister, "Only magister");
        _;
    }

    function initialize(
        address token,
        address shares,
        address distributor,
        address initialMagister,
        address /* admin */
    ) external initializer {
        require(initialMagister != address(0), "Invalid magister");
        _initializeTreasury(token, shares, distributor);
        magister = initialMagister;
        pettyLimit = 1_000 ether;
        standardLimit = 10_000 ether;
        majorLimit = 50_000 ether;
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

        if (prop.pType == ProposalType.MagisterElection || prop.pType == ProposalType.SpendingLimitsPackage) {
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
            (uint256 p, uint256 s, uint256 m) = abi.decode(prop.data, (uint256, uint256, uint256));
            pettyLimit = p;
            standardLimit = s;
            majorLimit = m;
            emit SpendingLimitsChanged(p, s, m);
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
