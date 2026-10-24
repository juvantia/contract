// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SyndicateFactoryFixture} from "./SyndicateFactory.t.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";
import {Syndicate} from "../src/community/Syndicate.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";

contract SyndicateGovernanceTest is SyndicateFactoryFixture {
    address internal junior = address(0xCAFE);
    address internal candidate = address(0xBABE);

    function _clan(uint8 bobGrade, uint8 carolGrade, uint8 daveGrade, uint8 preset) internal returns (Syndicate) {
        SyndicateFactory.SyndicateDeploymentVoucher memory v = _buildVoucher(keccak256("governance"), preset);
        v.members = new address[](daveGrade == 0 ? 2 : 3);
        v.memberGrades = new uint8[](v.members.length);
        v.members[0] = bob;
        v.members[1] = carol;
        v.memberGrades[0] = bobGrade;
        v.memberGrades[1] = carolGrade;
        if (daveGrade != 0) {
            v.members[2] = dave;
            v.memberGrades[2] = daveGrade;
        }
        return Syndicate(factory.createSyndicate(v, _signVoucher(v)));
    }

    function _join(Syndicate clan, address who, uint8 grade) internal {
        vm.prank(clan.primus());
        clan.inviteMember(who, grade);
        vm.prank(who);
        clan.acceptInvitation();
    }

    function _propose(Syndicate clan, address voter, Syndicate.ActionType kind, address target, uint8 grade)
        internal
        returns (uint256)
    {
        vm.prank(voter);
        return clan.proposeAction(kind, target, grade);
    }

    function _support(Syndicate clan, address voter, uint256 action) internal {
        vm.prank(voter);
        clan.supportAction(action);
    }

    function testJuniorCannotIssueLowGradeInvitationThroughGenericProposal() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        _join(clan, junior, 1);
        vm.prank(junior);
        vm.expectRevert("Only primus");
        clan.proposeAction(Syndicate.ActionType.AddMember, candidate, 1);
        assertEq(clan.invitations(candidate), 0);
        _propose(clan, alice, Syndicate.ActionType.AddMember, candidate, 2);
        assertEq(clan.invitations(candidate), 2);
        assertFalse(clan.isMember(candidate));
        vm.prank(candidate);
        clan.acceptInvitation();
        assertTrue(clan.isMember(candidate));
    }

    function testOneOfNinetySevenVotesCannotDemoteCofounder() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        _join(clan, junior, 1);
        uint256 action = _propose(clan, junior, Syndicate.ActionType.ChangeGrade, bob, 1);
        assertEq(clan.memberGrades(bob), 6);
        assertFalse(clan.isActionThresholdMet(action));
        (,,, uint256 votes,) = clan.actions(action);
        assertEq(votes, 1);
    }

    function testDirectPrimusDemotionCannotBypassCofounderVote() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        vm.prank(alice);
        vm.expectRevert("Threshold not met, requires voting action");
        clan.changeGrade(bob, 2);
        assertEq(clan.memberGrades(bob), 6);
        assertEq(clan.actionCount(), 0);
        vm.prank(alice);
        vm.expectRevert("Threshold not met, requires voting action");
        clan.removeMember(bob);
    }

    function testCofounderDemotionNeedsBothEligibleFounders() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.ChangeGrade, bob, 2);
        assertEq(clan.memberGrades(bob), 6);
        vm.prank(bob);
        vm.expectRevert(Syndicate.IneligibleVoter.selector);
        clan.supportAction(action);
        _support(clan, carol, action);
        assertEq(clan.memberGrades(bob), 2);
        assertEq(clan.memberWeights(bob), 2);
        assertEq(clan.totalWeight(), 66);
    }

    function testDemocraticPresetAlsoProtectsCofounderDemotion() public {
        Syndicate clan = _clan(6, 6, 0, 1);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.ChangeGrade, bob, 1);
        assertEq(clan.memberGrades(bob), 6);
        _support(clan, carol, action);
        assertEq(clan.memberGrades(bob), 1);
        assertEq(clan.totalWeight(), 17);
    }

    function testLowGradePromotionStillNeedsPrimusAuthority() public {
        Syndicate clan = _clan(1, 6, 0, 0);
        vm.prank(bob);
        vm.expectRevert("Only primus");
        clan.proposeAction(Syndicate.ActionType.ChangeGrade, bob, 2);
        vm.prank(alice);
        clan.changeGrade(bob, 2);
        assertEq(clan.memberGrades(bob), 2);
    }

    function testPromotionUsesNewRankThreshold() public {
        Syndicate clan = _clan(2, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.ChangeGrade, bob, 6);
        assertEq(clan.memberGrades(bob), 2);
        _support(clan, carol, action);
        assertEq(clan.memberGrades(bob), 6);
    }

    function testStaleKickAfterTargetExitCannotCorruptMembershipArray() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(bob);
        clan.removeMember(bob);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(action);
        assertEq(clan.memberCount(), 2);
        assertEq(clan.members(0), alice);
        assertEq(clan.members(1), carol);
        assertTrue(clan.isMember(alice));
        assertTrue(clan.isMember(carol));
        assertEq(clan.totalWeight(), 64);
    }

    function testStaleKickCannotTargetRejoinedMembership() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(bob);
        clan.removeMember(bob);
        _join(clan, bob, 2);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(action);
        assertTrue(clan.isMember(bob));
        assertEq(clan.memberGrades(bob), 2);
        assertEq(clan.memberCount(), 3);
    }

    function testStaleKickCannotRemoveCurrentPrimus() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(alice);
        clan.setPrimus(bob);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(action);
        assertEq(clan.primus(), bob);
        assertTrue(clan.isMember(bob));
        assertEq(clan.memberGrades(bob), 6);
    }

    function testPrimusRoleCycleDoesNotReviveOldKick() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(alice);
        clan.setPrimus(bob);
        vm.prank(bob);
        clan.setPrimus(alice);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(action);
    }

    function testRankChangeInvalidatesOldProtectedRankAction() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 kick = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        uint256 demotion = _propose(clan, alice, Syndicate.ActionType.ChangeGrade, bob, 2);
        _support(clan, carol, demotion);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(kick);
        assertTrue(clan.isMember(bob));
    }

    function testNewMembersCannotVoteOnExistingAction() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        _join(clan, junior, 2);
        vm.prank(junior);
        vm.expectRevert(Syndicate.IneligibleVoter.selector);
        clan.supportAction(action);
        _support(clan, carol, action);
        assertFalse(clan.isMember(bob));
        assertTrue(clan.isMember(junior));
    }

    function testRejoinedVoterCannotUseOldMembershipVotingWeight() public {
        Syndicate clan = _clan(6, 6, 6, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(carol);
        clan.removeMember(carol);
        _join(clan, carol, 2);
        vm.prank(carol);
        vm.expectRevert(Syndicate.IneligibleVoter.selector);
        clan.supportAction(action);
        _support(clan, dave, action);
        assertFalse(clan.isActionThresholdMet(action));
        assertTrue(clan.isMember(bob));
    }

    function testSnapshotWeightsDoNotIncreaseAfterVoterPromotion() public {
        Syndicate clan = _clan(6, 1, 6, 0);
        uint256 kick = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        uint256 promotion = _propose(clan, bob, Syndicate.ActionType.ChangeGrade, carol, 6);
        _support(clan, alice, promotion);
        _support(clan, dave, promotion);
        assertEq(clan.memberWeights(carol), 32);
        _support(clan, carol, kick);
        (,,, uint256 votes,) = clan.actions(kick);
        assertEq(votes, 33); // Alice's 32 plus Carol's original 1.
        assertFalse(clan.isActionThresholdMet(kick));
        _support(clan, dave, kick);
        assertFalse(clan.isMember(bob));
    }

    function testEligibleBaseDoesNotShrinkAfterOtherMemberLeaves() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(carol);
        clan.removeMember(carol);
        assertFalse(clan.isActionThresholdMet(action));
        assertTrue(clan.isMember(bob));
    }

    function testValidSnapshotVoteRemainsConsistentAfterVoterLeaves() public {
        Syndicate clan = _clan(6, 6, 6, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        _support(clan, carol, action);
        vm.prank(carol);
        clan.removeMember(carol);
        assertFalse(clan.isActionThresholdMet(action));
        _support(clan, dave, action);
        assertFalse(clan.isMember(bob));
        assertEq(clan.totalWeight(), 64);
    }

    function testLeadershipCycleInvalidatesOldReplacementAction() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, bob, Syndicate.ActionType.ReplacePrimus, carol, 0);
        vm.prank(alice);
        clan.setPrimus(bob);
        vm.prank(bob);
        clan.setPrimus(alice);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(action);
        assertEq(clan.primus(), alice);
    }

    function testGradeOneKickNeedsMoreThanExactHalf() public {
        Syndicate clan = _clan(1, 6, 0, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        assertTrue(clan.isMember(bob));
        assertFalse(clan.isActionThresholdMet(action));
        _support(clan, carol, action);
        assertFalse(clan.isMember(bob));
    }

    function testPendingAdmissionDoesNotOverrideCancelledInvitation() public {
        Syndicate clan = _clan(6, 6, 0, 0);
        uint256 action = _propose(clan, bob, Syndicate.ActionType.AddMember, candidate, 6);
        vm.prank(alice);
        clan.inviteMember(candidate, 1);
        vm.prank(alice);
        clan.cancelInvitation(candidate);
        vm.prank(carol);
        vm.expectRevert(Syndicate.StaleAction.selector);
        clan.supportAction(action);
        assertEq(clan.invitations(candidate), 0);
    }

    function testSnapshotVoteCannotBeCountedTwice() public {
        Syndicate clan = _clan(6, 6, 6, 0);
        uint256 action = _propose(clan, alice, Syndicate.ActionType.KickMember, bob, 0);
        _support(clan, carol, action);
        vm.prank(carol);
        vm.expectRevert(Syndicate.IneligibleVoter.selector);
        clan.supportAction(action);
        (,,, uint256 votes,) = clan.actions(action);
        assertEq(votes, 64);
        assertTrue(clan.isMember(bob));
    }
}

contract SyndicateDecimalToken is ERC20 {
    uint8 private immutable precision;

    constructor(uint8 decimals_) ERC20("Local euro fixture", "LOCAL") {
        precision = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return precision;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract SyndicateDecimalsTest is Test {
    address private alice = address(0xA11CE);
    address private recipient = address(0xCAFE);

    function _configure(uint8 decimals_)
        private
        returns (SyndicateDecimalToken token, Syndicate clan, JuvantiaRevenueDistributor distributor)
    {
        token = new SyndicateDecimalToken(decimals_);
        JuvantiaAerarium budget = new JuvantiaAerarium(address(token), address(this));
        distributor = new JuvantiaRevenueDistributor(address(token), address(this), address(budget));
        JuvantiaPaymentRegistry rules = new JuvantiaPaymentRegistry(address(this));
        distributor.setPaymentRegistry(address(rules));
        budget.configureSettlement(address(rules), address(distributor));
        rules.publish(keccak256("expense"), JuvantiaPaymentRegistry.Rule(true, true, 1, 0, 0));
        clan = Syndicate(Clones.clone(address(new Syndicate())));
    }

    function _params(SyndicateDecimalToken token, JuvantiaRevenueDistributor distributor)
        private
        view
        returns (Syndicate.SyndicateInitParams memory)
    {
        return Syndicate.SyndicateInitParams({
            token: address(token),
            distributor: address(distributor),
            primus: alice,
            preset: Syndicate.PresetType.DominantLeadership,
            grades: 6,
            members: new address[](0),
            memberGrades: new uint8[](0),
            admin: address(this),
            tribunal: address(0)
        });
    }

    function testSixDecimalDefaultsAndPettySpendingUseActualBaseUnits() public {
        (SyndicateDecimalToken token, Syndicate clan, JuvantiaRevenueDistributor distributor) = _configure(6);
        clan.initialize(_params(token, distributor));
        assertEq(clan.pettyLimit(), 500 * 1e6);
        assertEq(clan.majorLimit(), 25_000 * 1e6);
        token.mint(address(clan), 1_000 * 1e6);
        vm.prank(alice);
        vm.expectRevert("Invalid or exceeding petty limit");
        clan.spendPetty(recipient, 501 * 1e6, keccak256("too much"), keccak256("expense"));
        vm.prank(alice);
        clan.spendPetty(recipient, 500 * 1e6, keccak256("approved"), keccak256("expense"));
        assertEq(clan.operatingBalance(), 500 * 1e6);
        assertEq(distributor.accountRevenue(recipient), 500 * 1e6);
        distributor.claimAccountFor(recipient);
        assertEq(token.balanceOf(recipient), 500 * 1e6);
    }

    function testUnsupportedDecimalsFailBeforeExponentOrLimitOverflow() public {
        (SyndicateDecimalToken token, Syndicate clan, JuvantiaRevenueDistributor distributor) = _configure(73);
        Syndicate.SyndicateInitParams memory params = _params(token, distributor);
        vm.expectRevert(Syndicate.InvalidTokenDecimals.selector);
        clan.initialize(params);
    }

    function testMaximumSupportedDecimalsKeepDefaultLimitsRepresentable() public {
        (SyndicateDecimalToken token, Syndicate clan, JuvantiaRevenueDistributor distributor) = _configure(72);
        clan.initialize(_params(token, distributor));
        assertEq(clan.pettyLimit(), 500 * 10 ** uint256(72));
        assertEq(clan.majorLimit(), 25_000 * 10 ** uint256(72));
    }
}
