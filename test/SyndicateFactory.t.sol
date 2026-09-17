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
            gradeCount: 5,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
    }

    function testCreateSyndicateWithValidVoucher() public {
        bytes32 draftId = keccak256("syn-draft-1");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0); // Hierarchical
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        assertTrue(clone != address(0));
        assertEq(factory.usedDrafts(draftId), true);
        assertEq(factory.syndicateById(draftId), clone);
        assertEq(factory.syndicatesCount(), 1);

        Syndicate syndicate = Syndicate(clone);
        assertEq(syndicate.primus(), alice);
        assertEq(syndicate.gradeCount(), 5);
        assertEq(syndicate.memberCount(), 2);
        assertTrue(syndicate.isMember(alice));
        assertTrue(syndicate.isMember(bob));
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

    function testHierarchicalPresetWeights() public {
        // Grade count = 5. Hierarchical: W(Gk) = 2^(k-1), Primus = 2^(5-1) = 16
        // G1 = 1, G2 = 2, G3 = 4, G4 = 8, G5 = 16, Primus = 16
        bytes32 draftId = keccak256("syn-hier");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(syndicate.PRIMUS_GRADE()), 16);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(2), 2);
        assertEq(syndicate.getWeightForGrade(3), 4);
        assertEq(syndicate.getWeightForGrade(4), 8);
        assertEq(syndicate.getWeightForGrade(5), 16);

        // Alice = Primus (16), Bob = G2 (2) -> totalWeight = 18
        assertEq(syndicate.totalWeight(), 18);
        assertEq(syndicate.pointsOf(alice), (uint256(16) * 100_000) / 18);
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 18);
    }

    function testProportionalPresetWeights() public {
        // Grade count = 5. Proportional: W(Gk) = k, Primus = 5
        bytes32 draftId = keccak256("syn-prop");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 1);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(syndicate.PRIMUS_GRADE()), 5);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(2), 2);
        assertEq(syndicate.getWeightForGrade(3), 3);
        assertEq(syndicate.getWeightForGrade(4), 4);
        assertEq(syndicate.getWeightForGrade(5), 5);
    }

    function testFlatPresetWeights() public {
        // Flat: W(Gk) = 1, Primus = 1
        bytes32 draftId = keccak256("syn-flat");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 2);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(syndicate.PRIMUS_GRADE()), 1);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(5), 1);
    }

    function testCoFoundersEqualWeightsAndPoints() public {
        // 7-grade Hierarchical clan: G7 = 2^(7-1) = 64. Primus = 64.
        bytes32 draftId = keccak256("syn-cofounders");
        address[] memory members = new address[](1);
        members[0] = bob;
        uint8[] memory grades = new uint8[](1);
        grades[0] = 7; // Bob is also Grade 7 co-founder

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "FounderSyndicate",
            primus: alice,
            presetType: 0, // Hierarchical
            gradeCount: 7,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // Both hold 64 weight
        assertEq(syndicate.memberWeights(alice), 64);
        assertEq(syndicate.memberWeights(bob), 64);
        assertEq(syndicate.totalWeight(), 128);

        // Exact equal 50% split = 50,000 APU points
        assertEq(syndicate.pointsOf(alice), 50_000);
        assertEq(syndicate.pointsOf(bob), 50_000);
        assertEq(syndicate.shareOf(alice), 5_000); // 50.00%
        assertEq(syndicate.shareOf(bob), 5_000);   // 50.00%
    }

    function testKickCoFounderProtectionEightyPercent() public {
        // 3 co-founders: Alice (Primus, G7=64), Bob (G7=64), Carol (G7=64)
        bytes32 draftId = keccak256("syn-3founders");
        address[] memory members = new address[](2);
        members[0] = bob;
        members[1] = carol;
        uint8[] memory grades = new uint8[](2);
        grades[0] = 7;
        grades[1] = 7;

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "TriSyndicate",
            primus: alice,
            presetType: 0,
            gradeCount: 7,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.totalWeight(), 192);

        // Alice tries to kick Bob directly -> reverts because threshold is 80% and Alice has 50% of eligible
        vm.prank(alice);
        vm.expectRevert("Threshold not met, requires voting action");
        syndicate.removeMember(bob);

        // Alice proposes kick action for Bob
        vm.prank(alice);
        uint256 actionId = syndicate.proposeAction(Syndicate.ActionType.KickMember, bob, 0);

        // Alice's vote (64) is logged. Eligible = 192 - 64 = 128.
        // Alice only holds 64 / 128 = 50% < 80%. Action is NOT executed!
        assertTrue(syndicate.isMember(bob));
        assertEq(syndicate.totalWeight(), 192);

        // Target Bob cannot vote on his own kick
        vm.prank(bob);
        vm.expectRevert("Target cannot vote on kick");
        syndicate.supportAction(actionId);

        // Carol supports the kick! Carol adds 64 votes -> 128 / 128 = 100% >= 80%
        // Executes instantly with ZERO delay!
        vm.prank(carol);
        syndicate.supportAction(actionId);

        assertFalse(syndicate.isMember(bob));
        assertEq(syndicate.totalWeight(), 128); // 192 - 64
        // Alice and Carol now hold 50,000 points each
        assertEq(syndicate.pointsOf(alice), 50_000);
        assertEq(syndicate.pointsOf(carol), 50_000);
    }

    function testPrimusImpeachmentZeroDelay() public {
        // Alice (Primus, G7=64), Bob (G7=64), Carol (G7=64)
        bytes32 draftId = keccak256("syn-impeach");
        address[] memory members = new address[](2);
        members[0] = bob;
        members[1] = carol;
        uint8[] memory grades = new uint8[](2);
        grades[0] = 7;
        grades[1] = 7;

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: draftId,
            name: "ImpeachSyndicate",
            primus: alice,
            presetType: 0,
            gradeCount: 7,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.primus(), alice);

        // Alice cannot propose self-impeachment
        vm.prank(alice);
        vm.expectRevert("Primus cannot propose self-impeachment");
        syndicate.proposeAction(Syndicate.ActionType.ReplacePrimus, bob, 0);

        // Bob proposes to replace Primus with Bob
        vm.prank(bob);
        uint256 actionId = syndicate.proposeAction(Syndicate.ActionType.ReplacePrimus, bob, 0);

        // Bob has 64 votes. Denominator = totalWeight - Alice = 192 - 64 = 128.
        // 64 / 128 = 50% < 75%. Not executed yet.
        assertEq(syndicate.primus(), alice);

        // Alice cannot vote on impeachment
        vm.prank(alice);
        vm.expectRevert("Primus cannot vote on impeachment");
        syndicate.supportAction(actionId);

        // Carol supports! 64 + 64 = 128 / 128 = 100% >= 75%.
        // Instantly executes with zero delay!
        vm.prank(carol);
        syndicate.supportAction(actionId);

        assertEq(syndicate.primus(), bob);
        // Alice is still an active member
        assertTrue(syndicate.isMember(alice));
    }

    function testAdmissionGradeThresholds() public {
        bytes32 draftId = keccak256("syn-admit");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // Grade 1 and 2: Primus unilateral (threshold = 0)
        vm.prank(alice);
        syndicate.addMember(dave, 2);
        assertTrue(syndicate.isMember(dave));

        // Adding to Grade 5 directly via addMember reverts (requires action proposal)
        address eve = address(0xEFE);
        vm.prank(alice);
        vm.expectRevert("Higher grades require voting action");
        syndicate.addMember(eve, 5);

        // Alice proposes to add Eve at Grade 5 (threshold 60%)
        // Alice has 16 weight out of total 16 + 2 + 2 = 20 weight (80% >= 60%)
        // Executes immediately!
        vm.prank(alice);
        syndicate.proposeAction(Syndicate.ActionType.AddMember, eve, 5);
        assertTrue(syndicate.isMember(eve));
        assertEq(syndicate.memberGrades(eve), 5);
    }

    function testDynamicDilutionAndConcentration() public {
        bytes32 draftId = keccak256("syn-dilution");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        voucher.members = new address[](0);
        voucher.memberGrades = new uint8[](0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // Solo Primus holds 100% = 100,000 points (weight 16 for gradeCount 5)
        assertEq(syndicate.pointsOf(alice), 100_000);
        assertEq(syndicate.shareOf(alice), 10_000);

        // Solo Primus proposes Carol at Grade 5 (16 weight) -> Alice holds 100% >= 60% -> executes instantly
        vm.prank(alice);
        syndicate.proposeAction(Syndicate.ActionType.AddMember, carol, 5);

        assertEq(syndicate.totalWeight(), 32);
        assertEq(syndicate.pointsOf(alice), 50_000);
        assertEq(syndicate.pointsOf(carol), 50_000);

        // Bob joins at Grade 2 directly (2 weight)
        vm.prank(alice);
        syndicate.addMember(bob, 2);

        assertEq(syndicate.totalWeight(), 34);
        assertEq(syndicate.pointsOf(alice), (uint256(16) * 100_000) / 34);
        assertEq(syndicate.pointsOf(carol), (uint256(16) * 100_000) / 34);
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 34);

        // Carol voluntarily leaves -> weight burns -> Alice and Bob concentrate!
        vm.prank(carol);
        syndicate.removeMember(carol);

        assertEq(syndicate.totalWeight(), 18);
        assertFalse(syndicate.isMember(carol));
        assertEq(syndicate.pointsOf(alice), (uint256(16) * 100_000) / 18);
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 18);
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
                preset: Syndicate.PresetType.Flat,
                grades: 3,
                members: new address[](0),
                memberGrades: new uint8[](0)
            })
        );
    }
}
