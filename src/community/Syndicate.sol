// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Gaming clan implementation with shared treasury, 100,000 APU-points scale, and zero-delay governance thresholds.
contract Syndicate is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum PresetType {
        DominantLeadership, // 0: W(Gk) = 2^(k-1), G1=1..G6=32
        DemocraticMass      // 1: Moderate: G1=1, G2=2, G3=3, G4=4, G5=6, G6=8
    }

    enum ActionType {
        AddMember,
        KickMember,
        ChangeGrade,
        ReplacePrimus
    }

    struct GovernanceAction {
        ActionType actionType;
        address target;
        uint8 grade;
        uint256 forVotes;
        bool executed;
    }

    uint8 public constant GRADE_COUNT = 6;
    uint8 public constant PRIMUS_REQUIRED_GRADE = 6;
    uint8 public constant PRIMUS_GRADE = 255; // Backward-compatibility alias

    IERC20 public paymentToken;
    address public primus;
    PresetType public presetType;
    uint8 public gradeCount;
    uint256 public totalWeight;

    uint256 public pettyLimit;
    uint256 public standardLimit;
    uint256 public majorLimit;

    mapping(address => bool) public isMember;
    mapping(address => uint256) public memberWeights;
    mapping(address => uint8) public memberGrades;
    address[] public members;
    mapping(address => uint256) private memberIndex;
    mapping(address => uint8) public invitations; // candidate => grade invited to

    uint256 public actionCount;
    mapping(uint256 => GovernanceAction) public actions;
    mapping(uint256 => mapping(address => bool)) public hasVotedAction;

    event PrimusChanged(address indexed oldPrimus, address indexed newPrimus);
    event MemberAdded(address indexed member, uint8 grade, uint256 weight);
    event MemberRemoved(address indexed member, uint256 burnedWeight);
    event GradeChanged(address indexed member, uint8 newGrade, uint256 newWeight);
    event InvitationSent(address indexed invitee, uint8 grade);
    event InvitationAccepted(address indexed invitee, uint8 grade);
    event InvitationDeclined(address indexed invitee);
    event InvitationCancelled(address indexed invitee);
    event OperatingDeposit(address indexed payer, bytes32 indexed referenceId, uint256 amount);
    event OperatingSpent(address indexed recipient, bytes32 indexed referenceId, uint256 amount);
    event ActionProposed(uint256 indexed actionId, ActionType indexed actionType, address indexed target, uint8 grade, address proposer);
    event ActionVoted(uint256 indexed actionId, address indexed voter, uint256 weight);
    event ActionExecuted(uint256 indexed actionId, ActionType indexed actionType, address indexed target);

    struct SyndicateInitParams {
        address token;
        address primus;
        PresetType preset;
        uint8 grades;
        address[] members;
        uint8[] memberGrades;
    }

    modifier onlyPrimus() {
        require(msg.sender == primus, "Only primus");
        _;
    }

    modifier onlyMember() {
        require(isMember[msg.sender], "Only member");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(SyndicateInitParams calldata params) external initializer {
        require(params.token.code.length > 0, "Invalid token");
        require(params.primus != address(0), "Invalid primus");
        require(params.grades == GRADE_COUNT, "Syndicate must have 6 grades");
        require(uint8(params.preset) <= 1, "Invalid preset");
        require(params.members.length == params.memberGrades.length, "Members and grades length mismatch");

        paymentToken = IERC20(params.token);
        primus = params.primus;
        presetType = params.preset;
        gradeCount = GRADE_COUNT;

        pettyLimit = 500 ether;
        standardLimit = 5_000 ether;
        majorLimit = 25_000 ether;

        // Register Primus as initial member holding Grade 6
        uint256 primusWeight = getWeightForGrade(PRIMUS_REQUIRED_GRADE);
        isMember[params.primus] = true;
        memberGrades[params.primus] = PRIMUS_REQUIRED_GRADE;
        memberWeights[params.primus] = primusWeight;
        totalWeight = primusWeight;

        memberIndex[params.primus] = 0;
        members.push(params.primus);

        emit PrimusChanged(address(0), params.primus);
        emit MemberAdded(params.primus, PRIMUS_REQUIRED_GRADE, primusWeight);

        // Register initial starting members if provided
        for (uint256 i = 0; i < params.members.length; i++) {
            _addMember(params.members[i], params.memberGrades[i]);
        }
    }

    function memberCount() external view returns (uint256) {
        return members.length;
    }

    /// @notice Returns weight for a grade according to clan preset. Primus holds Grade 6.
    function getWeightForGrade(uint8 grade) public view returns (uint256) {
        if (grade == PRIMUS_GRADE) {
            grade = PRIMUS_REQUIRED_GRADE;
        }

        require(grade >= 1 && grade <= GRADE_COUNT, "Invalid grade");
        if (presetType == PresetType.DominantLeadership) {
            return 2 ** (grade - 1); // G1=1, G2=2, G3=4, G4=8, G5=16, G6=32
        } else {
            // DemocraticMass (Moderate): G1=1, G2=2, G3=3, G4=4, G5=6, G6=8
            if (grade == 1) return 1;
            if (grade == 2) return 2;
            if (grade == 3) return 3;
            if (grade == 4) return 4;
            if (grade == 5) return 6;
            return 8; // grade 6
        }
    }

    /// @notice Returns admission threshold in basis points (10000 = 100.00%).
    function getAdmissionThreshold(uint8 grade) public pure returns (uint256) {
        if (grade <= 2) return 0;       // G1, G2: Primus unilateral
        if (grade == 3) return 5_000;   // G3: 50.0%
        if (grade == 4) return 5_500;   // G4: 55.0%
        if (grade == 5) return 6_000;   // G5: 60.0%
        return 6_667;                   // G6: 66.67% (2/3)
    }

    /// @notice Returns kick threshold in basis points (10000 = 100.00%).
    function getKickThreshold(uint8 grade) public pure returns (uint256) {
        if (grade == 1) return 5_001;   // G1: > 50.0% (simple majority)
        if (grade == 2) return 5_000;   // G2: 50.0%
        if (grade == 3) return 5_500;   // G3: 55.0%
        if (grade == 4) return 6_000;   // G4: 60.0%
        if (grade == 5) return 6_667;   // G5: 66.67% (2/3)
        return 8_000;                   // G6: 80.0% (4/5)
    }

    /// @notice Normalized APU-points on the fixed 100,000 total clan scale.
    function pointsOf(address member) public view returns (uint256) {
        if (!isMember[member] || totalWeight == 0) return 0;
        return Math.mulDiv(memberWeights[member], 100_000, totalWeight);
    }

    /// @notice Share basis points (where 10,000 = 100.00%).
    function shareOf(address member) public view returns (uint256) {
        if (!isMember[member] || totalWeight == 0) return 0;
        return Math.mulDiv(memberWeights[member], 10_000, totalWeight);
    }

    /// @notice Issue an invitation directly if admission threshold is 0 (G1 or G2). Higher grades require action proposal.
    /// Candidate must accept onchain via acceptInvitation().
    function inviteMember(address newMember, uint8 grade) public onlyPrimus {
        require(getAdmissionThreshold(grade) == 0, "Higher grades require voting action");
        require(newMember != address(0) && newMember != address(this), "Invalid address");
        require(!isMember[newMember], "Already member");
        require(grade >= 1 && grade <= GRADE_COUNT, "Invalid grade");

        invitations[newMember] = grade;
        emit InvitationSent(newMember, grade);
    }

    /// @notice Backward-compatible alias for inviteMember.
    function addMember(address newMember, uint8 grade) external onlyPrimus {
        inviteMember(newMember, grade);
    }

    /// @notice Candidate confirms and accepts the pending invitation with their own onchain transaction/signature.
    function acceptInvitation() external {
        uint8 grade = invitations[msg.sender];
        require(grade > 0, "No pending invitation");
        delete invitations[msg.sender];

        _addMember(msg.sender, grade);
        emit InvitationAccepted(msg.sender, grade);
    }

    /// @notice Candidate explicitly declines the invitation.
    function declineInvitation() external {
        require(invitations[msg.sender] > 0, "No pending invitation");
        delete invitations[msg.sender];
        emit InvitationDeclined(msg.sender);
    }

    /// @notice Primus cancels a pending invitation.
    function cancelInvitation(address invitee) external onlyPrimus {
        require(invitations[invitee] > 0, "No pending invitation");
        delete invitations[invitee];
        emit InvitationCancelled(invitee);
    }

    function _addMember(address newMember, uint8 grade) internal {
        require(newMember != address(0) && newMember != address(this), "Invalid address");
        require(!isMember[newMember], "Already member");
        require(grade >= 1 && grade <= GRADE_COUNT, "Invalid grade");

        uint256 weight = getWeightForGrade(grade);
        isMember[newMember] = true;
        memberGrades[newMember] = grade;
        memberWeights[newMember] = weight;
        totalWeight += weight;

        memberIndex[newMember] = members.length;
        members.push(newMember);

        emit MemberAdded(newMember, grade, weight);
    }

    /// @notice Remove a member: self-exit always allowed; Primus kick allowed if Primus alone meets threshold.
    function removeMember(address member) external {
        require(isMember[member], "Not a member");
        require(member != primus, "Cannot remove primus");

        if (msg.sender == member) {
            _removeMember(member);
            return;
        }

        require(msg.sender == primus, "Only primus or self");
        uint256 kickThreshold = getKickThreshold(memberGrades[member]);
        uint256 eligibleWeight = totalWeight - memberWeights[member];
        require(eligibleWeight > 0, "No eligible weight");

        if (kickThreshold == 5_001) {
            require(memberWeights[primus] * 10_000 > 5_000 * eligibleWeight, "Threshold not met, requires voting action");
        } else {
            require(memberWeights[primus] * 10_000 >= kickThreshold * eligibleWeight, "Threshold not met, requires voting action");
        }

        _removeMember(member);
    }

    function _removeMember(address member) internal {
        uint256 weight = memberWeights[member];
        totalWeight -= weight;
        delete memberWeights[member];
        delete memberGrades[member];
        delete isMember[member];

        // O(1) swap and pop
        uint256 idx = memberIndex[member];
        uint256 lastIdx = members.length - 1;
        if (idx != lastIdx) {
            address lastMember = members[lastIdx];
            members[idx] = lastMember;
            memberIndex[lastMember] = idx;
        }
        members.pop();
        delete memberIndex[member];

        emit MemberRemoved(member, weight);
    }

    /// @notice Direct grade change if new grade has threshold 0 (G1, G2); higher grades require voting action.
    function changeGrade(address member, uint8 newGrade) external onlyPrimus {
        require(getAdmissionThreshold(newGrade) == 0, "Higher grades require voting action");
        _changeGrade(member, newGrade);
    }

    function _changeGrade(address member, uint8 newGrade) internal {
        require(member != primus, "Cannot change primus grade");
        require(isMember[member], "Not a member");
        require(newGrade >= 1 && newGrade <= GRADE_COUNT, "Invalid grade");
        require(memberGrades[member] != newGrade, "Same grade");

        uint256 oldWeight = memberWeights[member];
        uint256 newWeight = getWeightForGrade(newGrade);

        totalWeight = totalWeight - oldWeight + newWeight;
        memberGrades[member] = newGrade;
        memberWeights[member] = newWeight;

        emit GradeChanged(member, newGrade, newWeight);
    }

    /// @notice Voluntary handover of Primus mantle by the current Primus. New Primus must be Grade 6.
    function setPrimus(address newPrimus) external onlyPrimus {
        require(isMember[newPrimus] && memberGrades[newPrimus] == PRIMUS_REQUIRED_GRADE, "Primus must be Grade 6");
        _setPrimus(newPrimus);
    }

    function _setPrimus(address newPrimus) internal {
        require(newPrimus != address(0) && newPrimus != address(this), "Invalid primus");
        require(newPrimus != primus, "Already primus");
        require(isMember[newPrimus] && memberGrades[newPrimus] == PRIMUS_REQUIRED_GRADE, "Primus must be Grade 6");

        address oldPrimus = primus;
        primus = newPrimus;
        emit PrimusChanged(oldPrimus, newPrimus);
    }

    /// @notice Propose a clan action (Admission G3..G6, Kick, GradeChange G3..G6, Replace Primus).
    function proposeAction(ActionType aType, address target, uint8 grade) external onlyMember returns (uint256 actionId) {
        if (aType == ActionType.AddMember) {
            require(target != address(0) && target != address(this), "Invalid address");
            require(!isMember[target], "Already member");
            require(grade >= 1 && grade <= GRADE_COUNT, "Invalid grade");
        } else if (aType == ActionType.KickMember) {
            require(isMember[target], "Not a member");
            require(target != primus, "Cannot kick primus");
            require(msg.sender != target, "Target cannot propose self-kick");
        } else if (aType == ActionType.ChangeGrade) {
            require(isMember[target], "Not a member");
            require(target != primus, "Cannot change primus grade");
            require(grade >= 1 && grade <= GRADE_COUNT, "Invalid grade");
            require(memberGrades[target] != grade, "Same grade");
        } else if (aType == ActionType.ReplacePrimus) {
            require(target != address(0) && target != address(this), "Invalid address");
            require(target != primus, "Already primus");
            require(isMember[target] && memberGrades[target] == PRIMUS_REQUIRED_GRADE, "New primus must be Grade 6");
            require(msg.sender != primus, "Primus cannot propose self-impeachment");
        }

        actionId = ++actionCount;
        GovernanceAction storage action = actions[actionId];
        action.actionType = aType;
        action.target = target;
        action.grade = grade;

        hasVotedAction[actionId][msg.sender] = true;
        uint256 voterWeight = memberWeights[msg.sender];
        action.forVotes = voterWeight;

        emit ActionProposed(actionId, aType, target, grade, msg.sender);
        emit ActionVoted(actionId, msg.sender, voterWeight);

        if (_isActionThresholdMet(actionId)) {
            _executeAction(actionId);
        }
    }

    /// @notice Support an active action. Zero-delay execution triggers instantly when threshold is met.
    function supportAction(uint256 actionId) external onlyMember {
        GovernanceAction storage action = actions[actionId];
        require(action.target != address(0), "Action not found");
        require(!action.executed, "Already executed");
        require(!hasVotedAction[actionId][msg.sender], "Already voted");

        if (action.actionType == ActionType.KickMember) {
            require(msg.sender != action.target, "Target cannot vote on kick");
        } else if (action.actionType == ActionType.ReplacePrimus) {
            require(msg.sender != primus, "Primus cannot vote on impeachment");
        }

        hasVotedAction[actionId][msg.sender] = true;
        uint256 voterWeight = memberWeights[msg.sender];
        action.forVotes += voterWeight;

        emit ActionVoted(actionId, msg.sender, voterWeight);

        if (_isActionThresholdMet(actionId)) {
            _executeAction(actionId);
        }
    }

    /// @notice Check if threshold is met for an action.
    function isActionThresholdMet(uint256 actionId) external view returns (bool) {
        return _isActionThresholdMet(actionId);
    }

    function _isActionThresholdMet(uint256 actionId) internal view returns (bool) {
        GovernanceAction storage action = actions[actionId];
        if (action.actionType == ActionType.AddMember || action.actionType == ActionType.ChangeGrade) {
            uint256 threshold = getAdmissionThreshold(action.grade);
            if (threshold == 0) return true;
            return action.forVotes * 10_000 >= threshold * totalWeight;
        } else if (action.actionType == ActionType.KickMember) {
            uint8 targetGrade = memberGrades[action.target];
            uint256 threshold = getKickThreshold(targetGrade);
            uint256 eligibleWeight = totalWeight - memberWeights[action.target];
            if (eligibleWeight == 0) return false;
            if (threshold == 5_001) {
                return action.forVotes * 10_000 > 5_000 * eligibleWeight;
            }
            return action.forVotes * 10_000 >= threshold * eligibleWeight;
        } else if (action.actionType == ActionType.ReplacePrimus) {
            uint256 eligibleWeight = totalWeight - memberWeights[primus];
            if (eligibleWeight == 0) return false;
            return action.forVotes * 10_000 >= 7_500 * eligibleWeight; // 75.0%
        }
        return false;
    }

    function _executeAction(uint256 actionId) internal {
        GovernanceAction storage action = actions[actionId];
        action.executed = true;

        if (action.actionType == ActionType.AddMember) {
            invitations[action.target] = action.grade;
            emit InvitationSent(action.target, action.grade);
        } else if (action.actionType == ActionType.KickMember) {
            _removeMember(action.target);
        } else if (action.actionType == ActionType.ChangeGrade) {
            _changeGrade(action.target, action.grade);
        } else if (action.actionType == ActionType.ReplacePrimus) {
            _setPrimus(action.target);
        }

        emit ActionExecuted(actionId, action.actionType, action.target);
    }

    /// @notice Operating treasury balance.
    function operatingBalance() public view returns (uint256) {
        return paymentToken.balanceOf(address(this));
    }

    /// @notice Deposit operating funds into Syndicate treasury.
    function depositOperating(uint256 amount, bytes32 referenceId) external nonReentrant {
        require(amount > 0, "Zero amount");
        uint256 beforeBalance = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        require(paymentToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");
        emit OperatingDeposit(msg.sender, referenceId, amount);
    }

    /// @notice Primus executes petty operational expenditure.
    function spendPetty(address recipient, uint256 amount, bytes32 referenceId) external onlyPrimus nonReentrant {
        require(recipient != address(0) && recipient != address(this), "Invalid recipient");
        require(amount > 0 && amount <= pettyLimit, "Invalid or exceeding petty limit");
        require(amount <= operatingBalance(), "Insufficient operating funds");

        paymentToken.safeTransfer(recipient, amount);
        emit OperatingSpent(recipient, referenceId, amount);
    }
}
