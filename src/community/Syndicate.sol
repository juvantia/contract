// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Gaming clan implementation with shared treasury and internal 100,000 APU-points scale.
contract Syndicate is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum PresetType {
        Hierarchical, // 0: W(Gk) = 2^(k-1), W(Primus) = 2^gradeCount
        Proportional, // 1: W(Gk) = k, W(Primus) = gradeCount + 1
        Flat          // 2: W(Gk) = 1, W(Primus) = 2
    }

    uint8 public constant PRIMUS_GRADE = 255;

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

    event PrimusChanged(address indexed oldPrimus, address indexed newPrimus);
    event MemberAdded(address indexed member, uint8 grade, uint256 weight);
    event MemberRemoved(address indexed member, uint256 burnedWeight);
    event GradeChanged(address indexed member, uint8 newGrade, uint256 newWeight);
    event OperatingDeposit(address indexed payer, bytes32 indexed referenceId, uint256 amount);
    event OperatingSpent(address indexed recipient, bytes32 indexed referenceId, uint256 amount);

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

    constructor() {
        _disableInitializers();
    }

    function initialize(SyndicateInitParams calldata params) external initializer {
        require(params.token.code.length > 0, "Invalid token");
        require(params.primus != address(0), "Invalid primus");
        require(params.grades >= 2 && params.grades <= 7, "Grades must be between 2 and 7");
        require(params.members.length == params.memberGrades.length, "Members and grades length mismatch");

        paymentToken = IERC20(params.token);
        primus = params.primus;
        presetType = params.preset;
        gradeCount = params.grades;

        pettyLimit = 500 ether;
        standardLimit = 5_000 ether;
        majorLimit = 25_000 ether;

        // Register Primus as initial member with Primus grade
        uint256 primusWeight = getWeightForGrade(PRIMUS_GRADE);
        isMember[params.primus] = true;
        memberGrades[params.primus] = PRIMUS_GRADE;
        memberWeights[params.primus] = primusWeight;
        totalWeight = primusWeight;

        memberIndex[params.primus] = 0;
        members.push(params.primus);

        emit PrimusChanged(address(0), params.primus);
        emit MemberAdded(params.primus, PRIMUS_GRADE, primusWeight);

        // Register initial starting members if provided
        for (uint256 i = 0; i < params.members.length; i++) {
            _addMember(params.members[i], params.memberGrades[i]);
        }
    }

    function memberCount() external view returns (uint256) {
        return members.length;
    }

    /// @notice Returns weight for a grade according to clan preset.
    function getWeightForGrade(uint8 grade) public view returns (uint256) {
        if (grade == PRIMUS_GRADE) {
            if (presetType == PresetType.Hierarchical) {
                return 2 ** gradeCount; // 2^gradeCount
            } else if (presetType == PresetType.Proportional) {
                return uint256(gradeCount) + 1;
            } else {
                return 2; // Flat: Primus has 2 weight
            }
        }

        require(grade >= 1 && grade <= gradeCount, "Invalid grade");
        if (presetType == PresetType.Hierarchical) {
            return 2 ** (grade - 1); // 2^(k-1)
        } else if (presetType == PresetType.Proportional) {
            return uint256(grade); // k
        } else {
            return 1; // Flat: 1 weight
        }
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

    /// @notice Add a new member to the syndicate with a starting grade.
    function addMember(address newMember, uint8 grade) external onlyPrimus {
        _addMember(newMember, grade);
    }

    function _addMember(address newMember, uint8 grade) internal {
        require(newMember != address(0) && newMember != address(this), "Invalid address");
        require(!isMember[newMember], "Already member");
        require(grade >= 1 && grade <= gradeCount, "Invalid grade");

        uint256 weight = getWeightForGrade(grade);
        isMember[newMember] = true;
        memberGrades[newMember] = grade;
        memberWeights[newMember] = weight;
        totalWeight += weight;

        memberIndex[newMember] = members.length;
        members.push(newMember);

        emit MemberAdded(newMember, grade, weight);
    }

    /// @notice Remove a member (Primus kick or member self-exit). Weight burns instantly in O(1).
    function removeMember(address member) external {
        require(msg.sender == primus || msg.sender == member, "Only primus or self");
        require(member != primus, "Cannot remove primus");
        require(isMember[member], "Not a member");

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

    /// @notice Promote or demote a member.
    function changeGrade(address member, uint8 newGrade) external onlyPrimus {
        require(member != primus, "Cannot change primus grade");
        require(isMember[member], "Not a member");
        require(newGrade >= 1 && newGrade <= gradeCount, "Invalid grade");
        require(memberGrades[member] != newGrade, "Same grade");

        uint256 oldWeight = memberWeights[member];
        uint256 newWeight = getWeightForGrade(newGrade);

        totalWeight = totalWeight - oldWeight + newWeight;
        memberGrades[member] = newGrade;
        memberWeights[member] = newWeight;

        emit GradeChanged(member, newGrade, newWeight);
    }

    /// @notice Transfer Primus leadership.
    function setPrimus(address newPrimus) external onlyPrimus {
        require(newPrimus != address(0) && newPrimus != address(this), "Invalid primus");
        require(newPrimus != primus, "Already primus");

        address oldPrimus = primus;
        uint256 primusWeight = getWeightForGrade(PRIMUS_GRADE);

        if (isMember[newPrimus]) {
            // Adjust weight for new Primus
            uint256 oldNewPrimusWeight = memberWeights[newPrimus];
            totalWeight = totalWeight - oldNewPrimusWeight + primusWeight;
        } else {
            isMember[newPrimus] = true;
            memberIndex[newPrimus] = members.length;
            members.push(newPrimus);
            totalWeight += primusWeight;
        }

        // Demote old primus to highest regular grade
        uint256 oldPrimusWeight = getWeightForGrade(gradeCount);
        memberGrades[oldPrimus] = gradeCount;
        memberWeights[oldPrimus] = oldPrimusWeight;
        totalWeight = totalWeight - primusWeight + oldPrimusWeight;

        // Set new primus
        memberGrades[newPrimus] = PRIMUS_GRADE;
        memberWeights[newPrimus] = primusWeight;
        primus = newPrimus;

        emit PrimusChanged(oldPrimus, newPrimus);
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
