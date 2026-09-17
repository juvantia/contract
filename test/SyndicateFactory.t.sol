// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";
import {Syndicate} from "../src/community/Syndicate.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SyndicateFactoryTest is ProtocolFixture {
    SyndicateFactory internal factory;
    Syndicate internal syndicateImpl;

    uint256 internal authorizerPrivateKey = 0xA11CE_516;
    address internal authorizer;
    address internal dave = address(0xDA7E);

    function setUp() public override {
        super.setUp();
        authorizer = vm.addr(authorizerPrivateKey);

        syndicateImpl = new Syndicate();
        SyndicateFactory factoryImpl = new SyndicateFactory(
            address(syndicateImpl),
            address(euroToken)
        );

        factory = SyndicateFactory(address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(SyndicateFactory.initialize, (address(this), authorizer))
        )));
    }

    function _signVoucher(SyndicateFactory.SyndicateDeploymentVoucher memory voucher)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = factory.hashVoucher(voucher);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _buildVoucher(bytes32 draftId, uint8 preset)
        internal
        view
        returns (SyndicateFactory.SyndicateDeploymentVoucher memory voucher)
    {
        address[] memory members = new address[](1);
        members[0] = bob;

        uint8[] memory grades = new uint8[](1);
        grades[0] = 2;

        voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "CyberLegion",
            primus: alice,
            presetType: preset,
            gradeCount: 6,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
    }

    function testCreateSyndicateWithValidVoucher() public {
        bytes32 draftId = keccak256("syn-draft-1");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0); // DominantLeadership
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        assertTrue(clone != address(0));
        assertEq(factory.usedDrafts(draftId), true);
        assertEq(factory.syndicateById(draftId), clone);
        assertEq(factory.syndicatesCount(), 1);

        Syndicate syndicate = Syndicate(clone);
        assertEq(syndicate.primus(), alice);
        assertEq(syndicate.gradeCount(), 6);
        assertEq(syndicate.memberCount(), 2);
        assertTrue(syndicate.isMember(alice));
        assertTrue(syndicate.isMember(bob));
        assertEq(syndicate.memberGrades(alice), 6);
    }

    function testSyndicateReplayProtection() public {
        bytes32 draftId = keccak256("syn-replay");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        factory.createSyndicate(voucher, sig);

        vm.expectRevert("Draft already used");
        factory.createSyndicate(voucher, sig);
    }

    function testSyndicateExpiredVoucherRejected() public {
        bytes32 draftId = keccak256("syn-expired");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        voucher.deadline = block.timestamp - 1;
        bytes memory sig = _signVoucher(voucher);

        vm.expectRevert("Voucher expired");
        factory.createSyndicate(voucher, sig);
    }

    function testSyndicateInvalidSignatureRejected() public {
        bytes32 draftId = keccak256("syn-bad-sig");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes32 digest = factory.hashVoucher(voucher);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD_BEEF, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid voucher signature");
        factory.createSyndicate(voucher, badSig);
    }

    function testDominantLeadershipPresetWeights() public {
        // 6 grades. DominantLeadership: W(Gk) = 2^(k-1). Primus = G6 = 32
        // G1 = 1, G2 = 2, G3 = 4, G4 = 8, G5 = 16, G6 = 32
        bytes32 draftId = keccak256("syn-dom");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(6), 32);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(2), 2);
        assertEq(syndicate.getWeightForGrade(3), 4);
        assertEq(syndicate.getWeightForGrade(4), 8);
        assertEq(syndicate.getWeightForGrade(5), 16);
        assertEq(syndicate.getWeightForGrade(6), 32);

        // Alice = Primus on G6 (32), Bob = G2 (2) -> totalWeight = 34
        assertEq(syndicate.totalWeight(), 34);
        assertEq(syndicate.pointsOf(alice), (uint256(32) * 100_000) / 34);
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 34);
    }

    function testDemocraticMassPresetWeights() public {
        // 6 grades. DemocraticMass (Moderate): G1=1, G2=2, G3=3, G4=4, G5=6, G6=8
        bytes32 draftId = keccak256("syn-dem");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 1);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(2), 2);
        assertEq(syndicate.getWeightForGrade(3), 3);
        assertEq(syndicate.getWeightForGrade(4), 4);
        assertEq(syndicate.getWeightForGrade(5), 6);
        assertEq(syndicate.getWeightForGrade(6), 8);

        // Alice (G6 = 8) + Bob (G2 = 2) = 10 total weight
        assertEq(syndicate.totalWeight(), 10);
        assertEq(syndicate.pointsOf(alice), 80_000);
        assertEq(syndicate.pointsOf(bob), 20_000);
    }

    function testCoFoundersEqualWeightsAndPoints() public {
        // 6-grade DominantLeadership clan: G6 = 32. Primus on G6 = 32.
        bytes32 draftId = keccak256("syn-cofounders");
        address[] memory members = new address[](1);
        members[0] = bob;
        uint8[] memory grades = new uint8[](1);
        grades[0] = 6; // Bob is also Grade 6 co-founder

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "FounderSyndicate",
            primus: alice,
            presetType: 0, // DominantLeadership
            gradeCount: 6,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.memberWeights(alice), 32);
        assertEq(syndicate.memberWeights(bob), 32);
        assertEq(syndicate.totalWeight(), 64);

        assertEq(syndicate.pointsOf(alice), 50_000);
        assertEq(syndicate.pointsOf(bob), 50_000);
        assertEq(syndicate.shareOf(alice), 5_000); // 50.00%
        assertEq(syndicate.shareOf(bob), 5_000);   // 50.00%
    }

    function testKickCoFounderProtectionEightyPercent() public {
        // 3 co-founders: Alice (Primus, G6=32), Bob (G6=32), Carol (G6=32)
        bytes32 draftId = keccak256("syn-3founders");
        address[] memory members = new address[](2);
        members[0] = bob;
        members[1] = carol;
        uint8[] memory grades = new uint8[](2);
        grades[0] = 6;
        grades[1] = 6;

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "TriSyndicate",
            primus: alice,
            presetType: 0,
            gradeCount: 6,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.totalWeight(), 96);

        // Alice tries to kick Bob directly -> reverts because threshold is 80% and Alice only has 50% of eligible (32/64)
        vm.prank(alice);
        vm.expectRevert("Threshold not met, requires voting action");
        syndicate.removeMember(bob);

        // Alice proposes kick action for Bob
        vm.prank(alice);
        uint256 actionId = syndicate.proposeAction(Syndicate.ActionType.KickMember, bob, 0);

        assertTrue(syndicate.isMember(bob));
        assertEq(syndicate.totalWeight(), 96);

        // Carol supports the kick! Carol adds 32 votes -> 64 / 64 = 100% >= 80%
        vm.prank(carol);
        syndicate.supportAction(actionId);

        assertFalse(syndicate.isMember(bob));
        assertEq(syndicate.totalWeight(), 64); // 96 - 32
        assertEq(syndicate.pointsOf(alice), 50_000);
        assertEq(syndicate.pointsOf(carol), 50_000);
    }

    function testPrimusImpeachmentZeroDelayAndGradeSixRequirement() public {
        // Alice (Primus, G6=32), Bob (G6=32), Carol (G6=32), Dave (G2=2)
        bytes32 draftId = keccak256("syn-impeach");
        address[] memory members = new address[](3);
        members[0] = bob;
        members[1] = carol;
        members[2] = dave;
        uint8[] memory grades = new uint8[](3);
        grades[0] = 6;
        grades[1] = 6;
        grades[2] = 2;

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "ImpeachSyndicate",
            primus: alice,
            presetType: 0,
            gradeCount: 6,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.primus(), alice);

        // Cannot propose non-Grade 6 member (Dave is Grade 2) as Primus
        vm.prank(bob);
        vm.expectRevert("New primus must be Grade 6");
        syndicate.proposeAction(Syndicate.ActionType.ReplacePrimus, dave, 0);

        // Bob proposes to replace Primus with Bob (Bob is Grade 6)
        vm.prank(bob);
        uint256 actionId = syndicate.proposeAction(Syndicate.ActionType.ReplacePrimus, bob, 0);

        // Bob has 32 votes out of eligible (98 - 32 = 66). 32 / 66 = 48.4% < 75%. Not executed yet.
        assertEq(syndicate.primus(), alice);

        // Carol supports! 32 + 32 = 64 votes out of 66 = 96.9% >= 75%.
        // Executes instantly with zero delay!
        vm.prank(carol);
        syndicate.supportAction(actionId);

        assertEq(syndicate.primus(), bob);
        assertTrue(syndicate.isMember(alice));
    }

    function testAdmissionGradeThresholds() public {
        bytes32 draftId = keccak256("syn-admit");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // Grade 1 and 2: Primus unilateral (threshold = 0) issues invitation
        vm.prank(alice);
        syndicate.inviteMember(dave, 2);
        assertFalse(syndicate.isMember(dave));
        assertEq(syndicate.invitations(dave), 2);

        // Dave confirms onchain via acceptInvitation()
        vm.prank(dave);
        syndicate.acceptInvitation();
        assertTrue(syndicate.isMember(dave));
        assertEq(syndicate.memberGrades(dave), 2);
        assertEq(syndicate.invitations(dave), 0);

        // Inviting to Grade 5 directly via inviteMember reverts
        address eve = address(0xEFE);
        vm.prank(alice);
        vm.expectRevert("Higher grades require voting action");
        syndicate.inviteMember(eve, 5);

        // Alice proposes to add Eve at Grade 5 (threshold 60%)
        // Alice has 32 weight out of total 32 + 2 + 2 = 36 weight (88.8% >= 60%)
        // Action executes, registering invitation for Eve!
        vm.prank(alice);
        syndicate.proposeAction(Syndicate.ActionType.AddMember, eve, 5);
        assertFalse(syndicate.isMember(eve));
        assertEq(syndicate.invitations(eve), 5);

        // Eve confirms onchain
        vm.prank(eve);
        syndicate.acceptInvitation();
        assertTrue(syndicate.isMember(eve));
        assertEq(syndicate.memberGrades(eve), 5);
        assertEq(syndicate.invitations(eve), 0);
    }

    function testDynamicDilutionAndConcentration() public {
        bytes32 draftId = keccak256("syn-dilution");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        voucher.members = new address[](0);
        voucher.memberGrades = new uint8[](0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // Solo Primus holds 100% = 100,000 points (weight 32 for Grade 6)
        assertEq(syndicate.pointsOf(alice), 100_000);
        assertEq(syndicate.shareOf(alice), 10_000);

        // Solo Primus proposes Carol at Grade 6 (32 weight) -> Alice holds 100% >= 66.7% -> executes invitation
        vm.prank(alice);
        syndicate.proposeAction(Syndicate.ActionType.AddMember, carol, 6);
        assertEq(syndicate.invitations(carol), 6);

        // Carol accepts invitation onchain
        vm.prank(carol);
        syndicate.acceptInvitation();

        assertEq(syndicate.totalWeight(), 64);
        assertEq(syndicate.pointsOf(alice), 50_000);
        assertEq(syndicate.pointsOf(carol), 50_000);

        // Bob invited at Grade 2 directly (2 weight)
        vm.prank(alice);
        syndicate.inviteMember(bob, 2);
        vm.prank(bob);
        syndicate.acceptInvitation();

        assertEq(syndicate.totalWeight(), 66);
        assertEq(syndicate.pointsOf(alice), (uint256(32) * 100_000) / 66);
        assertEq(syndicate.pointsOf(carol), (uint256(32) * 100_000) / 66);
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 66);

        // Carol voluntarily leaves -> weight burns -> Alice and Bob concentrate!
        vm.prank(carol);
        syndicate.removeMember(carol);

        assertEq(syndicate.totalWeight(), 34);
        assertFalse(syndicate.isMember(carol));
        assertEq(syndicate.pointsOf(alice), (uint256(32) * 100_000) / 34);
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 34);
    }

    function testPrimusPettySpending() public {
        bytes32 draftId = keccak256("syn-spend");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        euroToken.approve(clone, 5_000 ether);
        syndicate.depositOperating(5_000 ether, keccak256("syn-dep"));
        assertEq(syndicate.operatingBalance(), 5_000 ether);

        vm.prank(bob);
        vm.expectRevert("Only primus");
        syndicate.spendPetty(bob, 100 ether, keccak256("syn-petty-1"));

        vm.prank(alice);
        syndicate.spendPetty(carol, 200 ether, keccak256("syn-petty-1"));
        assertEq(euroToken.balanceOf(carol), 200 ether);
        assertEq(syndicate.operatingBalance(), 4_800 ether);

        vm.prank(alice);
        vm.expectRevert("Invalid or exceeding petty limit");
        syndicate.spendPetty(carol, 600 ether, keccak256("syn-petty-2"));
    }

    function testCannotReinitializeSyndicate() public {
        bytes32 draftId = keccak256("syn-init");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);

        vm.expectRevert();
        Syndicate(clone).initialize(
            Syndicate.SyndicateInitParams({
                token: address(euroToken),
                primus: bob,
                preset: Syndicate.PresetType.DemocraticMass,
                grades: 6,
                members: new address[](0),
                memberGrades: new uint8[](0)
            })
        );
    }

    function testInvitationDeclinedAndCancelled() public {
        bytes32 draftId = keccak256("syn-invites");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // 1. Decline flow
        vm.prank(alice);
        syndicate.inviteMember(dave, 1);
        assertEq(syndicate.invitations(dave), 1);

        vm.prank(dave);
        syndicate.declineInvitation();
        assertEq(syndicate.invitations(dave), 0);
        assertFalse(syndicate.isMember(dave));

        // 2. Cancel flow
        vm.prank(alice);
        syndicate.inviteMember(dave, 2);
        assertEq(syndicate.invitations(dave), 2);

        vm.prank(bob);
        vm.expectRevert("Only primus");
        syndicate.cancelInvitation(dave);

        vm.prank(alice);
        syndicate.cancelInvitation(dave);
        assertEq(syndicate.invitations(dave), 0);
        assertFalse(syndicate.isMember(dave));
    }
}
