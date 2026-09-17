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
        // Grade count = 5. Hierarchical: W(Gk) = 2^(k-1), Primus = 2^5 = 32
        // G1 = 1, G2 = 2, G3 = 4, G4 = 8, G5 = 16, Primus = 32
        bytes32 draftId = keccak256("syn-hier");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(syndicate.PRIMUS_GRADE()), 32);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(2), 2);
        assertEq(syndicate.getWeightForGrade(3), 4);
        assertEq(syndicate.getWeightForGrade(4), 8);
        assertEq(syndicate.getWeightForGrade(5), 16);

        // Alice = Primus (32), Bob = G2 (2) -> totalWeight = 34
        assertEq(syndicate.totalWeight(), 34);
        assertEq(syndicate.pointsOf(alice), (uint256(32) * 100_000) / 34); // ~94,117
        assertEq(syndicate.pointsOf(bob), (uint256(2) * 100_000) / 34);    // ~5,882
    }

    function testProportionalPresetWeights() public {
        // Grade count = 5. Proportional: W(Gk) = k, Primus = 5 + 1 = 6
        bytes32 draftId = keccak256("syn-prop");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 1);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(syndicate.PRIMUS_GRADE()), 6);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(2), 2);
        assertEq(syndicate.getWeightForGrade(3), 3);
        assertEq(syndicate.getWeightForGrade(4), 4);
        assertEq(syndicate.getWeightForGrade(5), 5);
    }

    function testFlatPresetWeights() public {
        // Flat: W(Gk) = 1, Primus = 2
        bytes32 draftId = keccak256("syn-flat");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 2);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        assertEq(syndicate.getWeightForGrade(syndicate.PRIMUS_GRADE()), 2);
        assertEq(syndicate.getWeightForGrade(1), 1);
        assertEq(syndicate.getWeightForGrade(5), 1);
    }

    function testDynamicDilutionAndConcentration() public {
        // Hierarchical preset: Primus Alice (32 weight)
        bytes32 draftId = keccak256("syn-dilution");
        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = _buildVoucher(draftId, 0);
        // Start with only Primus (no extra members)
        voucher.members = new address[](0);
        voucher.memberGrades = new uint8[](0);
        bytes memory sig = _signVoucher(voucher);

        address clone = factory.createSyndicate(voucher, sig);
        Syndicate syndicate = Syndicate(clone);

        // Solo Primus holds 100% = 100,000 points
        assertEq(syndicate.pointsOf(alice), 100_000);
        assertEq(syndicate.shareOf(alice), 10_000); // 100.00%

        // Carol joins at Grade 5 (16 weight)
        vm.prank(alice);
        syndicate.addMember(carol, 5);

        // totalWeight = 32 + 16 = 48
        assertEq(syndicate.totalWeight(), 48);
        // Alice diluted: (32 * 100,000) / 48 = 66,666
        assertEq(syndicate.pointsOf(alice), 66_666);
        // Carol receives: (16 * 100,000) / 48 = 33,333
        assertEq(syndicate.pointsOf(carol), 33_333);
        // Sum is preserved around 100,000 (modulo rounding)
        assertTrue(syndicate.pointsOf(alice) + syndicate.pointsOf(carol) >= 99_999);

        // Bob joins at Grade 4 (8 weight)
        vm.prank(alice);
        syndicate.addMember(bob, 4);

        // totalWeight = 48 + 8 = 56
        assertEq(syndicate.totalWeight(), 56);
        assertEq(syndicate.pointsOf(alice), (uint256(32) * 100_000) / 56); // 57,142
        assertEq(syndicate.pointsOf(carol), (uint256(16) * 100_000) / 56); // 28,571
        assertEq(syndicate.pointsOf(bob), (uint256(8) * 100_000) / 56);   // 14,285

        // Carol leaves (removes herself) -> weight burns -> Alice and Bob concentrate!
        vm.prank(carol);
        syndicate.removeMember(carol);

        // totalWeight = 56 - 16 = 40
        assertEq(syndicate.totalWeight(), 40);
        assertEq(syndicate.isMember(carol), false);
        assertEq(syndicate.pointsOf(carol), 0);
        assertEq(syndicate.pointsOf(alice), (uint256(32) * 100_000) / 40); // 80,000 (concentrated back up!)
        assertEq(syndicate.pointsOf(bob), (uint256(8) * 100_000) / 40);   // 20,000
        assertEq(syndicate.pointsOf(alice) + syndicate.pointsOf(bob), 100_000);
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

        // Non-primus cannot spend
        vm.prank(bob);
        vm.expectRevert("Only primus");
        syndicate.spendPetty(bob, 100 ether, keccak256("syn-petty-1"));

        // Primus spends within petty limit (pettyLimit = 500 ether)
        vm.prank(alice);
        syndicate.spendPetty(carol, 200 ether, keccak256("syn-petty-1"));
        assertEq(euroToken.balanceOf(carol), 200 ether);
        assertEq(syndicate.operatingBalance(), 4_800 ether);

        // Primus exceeds petty limit -> reverts
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
