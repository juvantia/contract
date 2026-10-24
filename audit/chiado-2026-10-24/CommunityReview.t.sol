// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConsortiumFactoryTest} from "../../test/ConsortiumFactory.t.sol";
import {SyndicateFactoryTest} from "../../test/SyndicateFactory.t.sol";
import {ConsortiumFactory} from "../../src/community/ConsortiumFactory.sol";
import {Consortium} from "../../src/community/Consortium.sol";
import {JuvantiaAsset} from "../../src/JuvantiaAsset.sol";
import {SyndicateFactory} from "../../src/community/SyndicateFactory.sol";
import {Syndicate} from "../../src/community/Syndicate.sol";

/// @dev Audit reproduction: passing tests confirm known incorrect behavior, not readiness.
contract ConsortiumReviewTest is ConsortiumFactoryTest {
    function testAuditSixtyPercentCanChangeLimitsDespiteSixtyFivePercentRequirement() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v = _buildVoucher(keccak256("review-limits"));
        v.incorporatorShares[0] = 48_000 ether;
        v.incorporatorShares[1] = 32_000 ether;
        (address clone,) = factory.createConsortium(v, _signVoucher(v));
        Consortium c = Consortium(clone);
        vm.prank(alice);
        uint256 proposal =
            c.propose(Consortium.ProposalType.SpendingLimitsPackage, abi.encode(2_000 ether, 80_000 ether), bytes32(0));
        vm.prank(alice);
        c.castVote(proposal, true);
        assertEq(c.pettyLimit(), 2_000 ether);
        assertEq(c.majorLimit(), 80_000 ether);
    }

    function testAuditSameSharesVoteThreeTimesToElectMinorityCandidate() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v = _buildVoucher(keccak256("review-vote"));
        (address clone, address token) = factory.createConsortium(v, _signVoucher(v));
        Consortium c = Consortium(clone);
        address attackerSecond = address(0xDADD);
        address attackerThird = address(0xDDEE);
        uint256 owned = JuvantiaAsset(token).balanceOf(bob);
        assertEq(owned * 4, c.circulatingSupply()); // attacker owns 25%.
        vm.prank(bob);
        uint256 proposal = c.propose(Consortium.ProposalType.MagisterElection, abi.encode(bob), bytes32(0));
        vm.startPrank(bob);
        c.castVote(proposal, true);
        JuvantiaAsset(token).transfer(attackerSecond, owned);
        vm.stopPrank();
        vm.startPrank(attackerSecond);
        c.castVote(proposal, true);
        JuvantiaAsset(token).transfer(attackerThird, owned);
        vm.stopPrank();
        assertEq(c.magister(), alice);
        vm.prank(attackerThird);
        c.castVote(proposal, true);
        assertEq(c.magister(), bob); // same 25% voted three times.
    }
}

contract SyndicateReviewTest is SyndicateFactoryTest {
    function testAuditAnyMemberCanUnilaterallyDemoteCofounderThroughAction() public {
        Syndicate s = _threeFounders();
        address junior = address(0xCAFE);
        vm.prank(alice);
        s.inviteMember(junior, 1);
        vm.prank(junior);
        s.acceptInvitation();
        vm.prank(junior);
        s.proposeAction(Syndicate.ActionType.ChangeGrade, bob, 1);
        assertEq(s.memberGrades(bob), 1);
        assertEq(s.memberWeights(bob), 1);
    }

    function _threeFounders() internal returns (Syndicate s) {
        SyndicateFactory.SyndicateDeploymentVoucher memory v = _buildVoucher(keccak256("review-syn"), 0);
        v.members = new address[](2);
        v.members[0] = bob;
        v.members[1] = carol;
        v.memberGrades = new uint8[](2);
        v.memberGrades[0] = 6;
        v.memberGrades[1] = 6;
        s = Syndicate(factory.createSyndicate(v, _signVoucher(v)));
    }

    function testAuditPrimusDemotesAndKicksEqualCofounderWithoutApproval() public {
        Syndicate s = _threeFounders();
        vm.prank(alice);
        vm.expectRevert("Threshold not met, requires voting action");
        s.removeMember(bob);
        vm.startPrank(alice);
        s.changeGrade(bob, 2);
        s.removeMember(bob);
        vm.stopPrank();
        assertFalse(s.isMember(bob));
        assertTrue(s.isMember(carol));
    }

    function testAuditStaleKickRemovesAnotherMemberFromEnumeration() public {
        Syndicate s = _threeFounders();
        vm.prank(alice);
        uint256 action = s.proposeAction(Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(bob);
        s.removeMember(bob);
        assertEq(s.memberCount(), 2);
        vm.prank(carol);
        s.supportAction(action);
        assertEq(s.memberCount(), 1);
        assertTrue(s.isMember(alice));
        assertTrue(s.isMember(carol));
        assertEq(s.members(0), carol); // Alice is still member, absent from members array.
        assertEq(s.totalWeight(), 64);
    }

    function testAuditStaleKickCanRemoveCurrentPrimus() public {
        Syndicate s = _threeFounders();
        vm.prank(alice);
        uint256 action = s.proposeAction(Syndicate.ActionType.KickMember, bob, 0);
        vm.prank(alice);
        s.setPrimus(bob);
        vm.prank(carol);
        s.supportAction(action);
        assertEq(s.primus(), bob);
        assertFalse(s.isMember(bob));
        assertEq(s.memberGrades(bob), 0);
    }
}
