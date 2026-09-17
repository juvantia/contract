// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ConsortiumFactoryTest is ProtocolFixture {
    ConsortiumFactory internal factory;
    Consortium internal consortiumImpl;
    JuvantiaAsset internal assetImpl;

    uint256 internal authorizerPrivateKey = 0xA11CE_516;
    address internal authorizer;

    function setUp() public override {
        super.setUp();
        authorizer = vm.addr(authorizerPrivateKey);

        consortiumImpl = new Consortium();
        assetImpl = new JuvantiaAsset();

        ConsortiumFactory factoryImpl = new ConsortiumFactory(
            address(consortiumImpl),
            address(assetImpl),
            address(revenue),
            address(aerarium)
        );

        factory = ConsortiumFactory(address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(ConsortiumFactory.initialize, (address(this), authorizer))
        )));

        revenue.setRegistrar(address(factory), true);
    }

    function _signVoucher(ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = factory.hashVoucher(voucher);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _buildVoucher(bytes32 draftId)
        internal
        view
        returns (ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher)
    {
        address[] memory founders = new address[](2);
        founders[0] = alice;
        founders[1] = bob;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 60_000 ether;
        shares[1] = 20_000 ether;

        voucher = ConsortiumFactory.ConsortiumDeploymentVoucher({
            draftId: draftId,
            name: "RoboCorp Consortium",
            symbol: "ROBO",
            magister: alice,
            founders: founders,
            founderShares: shares,
            treasuryShares: 20_000 ether,
            deadline: block.timestamp + 1 hours,
            salt: draftId
        });
    }

    function testCreateConsortiumWithValidVoucher() public {
        bytes32 draftId = keccak256("draft-1");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone, address aClone) = factory.createConsortium(voucher, sig);

        assertTrue(cClone != address(0));
        assertTrue(aClone != address(0));
        assertEq(factory.usedDrafts(draftId), true);
        assertEq(factory.consortiumById(draftId), cClone);
        assertEq(factory.assetById(draftId), aClone);
        assertEq(factory.consortiaCount(), 1);

        // Check share distribution
        assertEq(JuvantiaAsset(aClone).balanceOf(alice), 60_000 ether);
        assertEq(JuvantiaAsset(aClone).balanceOf(bob), 20_000 ether);
        assertEq(JuvantiaAsset(aClone).balanceOf(cClone), 20_000 ether);
        assertEq(JuvantiaAsset(aClone).totalSupply(), 100_000 ether);

        // Check Consortium state
        Consortium consortium = Consortium(cClone);
        assertEq(consortium.magister(), alice);
        assertEq(consortium.treasuryShares(), 20_000 ether);
        assertEq(consortium.circulatingSupply(), 80_000 ether);
    }

    function testReplayProtection() public {
        bytes32 draftId = keccak256("draft-replay");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        factory.createConsortium(voucher, sig);

        vm.expectRevert("Draft already used");
        factory.createConsortium(voucher, sig);
    }

    function testExpiredVoucherRejected() public {
        bytes32 draftId = keccak256("draft-expired");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        voucher.deadline = block.timestamp - 1;
        bytes memory sig = _signVoucher(voucher);

        vm.expectRevert("Voucher expired");
        factory.createConsortium(voucher, sig);
    }

    function testInvalidSignatureRejected() public {
        bytes32 draftId = keccak256("draft-bad-sig");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);

        // Sign with a different key
        bytes32 digest = factory.hashVoucher(voucher);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD_BEEF, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid voucher signature");
        factory.createConsortium(voucher, badSig);
    }

    function testMismatchedShareSumRejected() public {
        bytes32 draftId = keccak256("draft-bad-shares");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        voucher.treasuryShares = 10_000 ether; // Total = 90,000 != 100,000
        bytes memory sig = _signVoucher(voucher);

        vm.expectRevert("Total shares must equal 100,000 ether");
        factory.createConsortium(voucher, sig);
    }

    function testCannotReinitializeConsortium() public {
        bytes32 draftId = keccak256("draft-init");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone, address aClone) = factory.createConsortium(voucher, sig);

        vm.expectRevert();
        Consortium(cClone).initialize(
            address(euroToken),
            aClone,
            address(revenue),
            bob,
            address(this)
        );
    }

    function testMagisterPettySpending() public {
        bytes32 draftId = keccak256("draft-petty");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone,) = factory.createConsortium(voucher, sig);
        Consortium consortium = Consortium(cClone);

        // Deposit 10,000 euro into consortium operating account
        euroToken.approve(cClone, 10_000 ether);
        consortium.depositOperating(10_000 ether, keccak256("deposit-1"));
        assertEq(consortium.operatingBalance(), 10_000 ether);

        // Non-magister cannot spend
        vm.prank(bob);
        vm.expectRevert("Only magister");
        consortium.spendOperating(bob, 500 ether, keccak256("inv-1"));

        // Magister spends within petty limit (pettyLimit = 1,000 ether)
        vm.prank(alice);
        consortium.spendOperating(carol, 500 ether, keccak256("inv-1"));
        assertEq(euroToken.balanceOf(carol), 500 ether);
        assertEq(consortium.operatingBalance(), 9_500 ether);

        // Magister exceeds petty limit -> reverts
        vm.prank(alice);
        vm.expectRevert("Exceeds petty limit");
        consortium.spendOperating(carol, 1_500 ether, keccak256("inv-2"));
    }

    function testConsortiumGovernanceMagisterElection() public {
        bytes32 draftId = keccak256("draft-gov");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone,) = factory.createConsortium(voucher, sig);
        Consortium consortium = Consortium(cClone);

        // Alice holds 60k of 80k circulating (75% > 50.001%)
        // Alice proposes Bob as new Magister
        vm.prank(alice);
        uint256 pId = consortium.propose(
            Consortium.ProposalType.MagisterElection,
            abi.encode(bob)
        );

        // Alice votes support -> crosses 50.001% threshold -> auto-executes!
        vm.prank(alice);
        consortium.castVote(pId, true);

        assertEq(consortium.magister(), bob);
    }

    function testConsortiumRevenueDistributionProposal() public {
        bytes32 draftId = keccak256("draft-rev-dist");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone,) = factory.createConsortium(voucher, sig);
        Consortium consortium = Consortium(cClone);

        euroToken.approve(cClone, 10_000 ether);
        consortium.depositOperating(10_000 ether, keccak256("deposit-ops"));

        // Alice (60k) + Bob (20k) = 80k circulating. Alice holds 60k = 75%
        vm.prank(alice);
        uint256 pId = consortium.propose(
            Consortium.ProposalType.RevenueDistribution,
            abi.encode(4_000 ether)
        );

        // Alice votes support (60k / 80k = 75% >= 75%) -> auto-executes!
        vm.prank(alice);
        consortium.castVote(pId, true);

        assertEq(consortium.distributablePool(), 4_000 ether);
        assertEq(consortium.operatingBalance(), 6_000 ether);

        // Alice (60k/80k = 75%) claims 3,000 ether
        uint256 aliceBefore = euroToken.balanceOf(alice);
        consortium.claimFor(alice);
        assertEq(euroToken.balanceOf(alice) - aliceBefore, 3_000 ether);

        // Bob (20k/80k = 25%) claims 1,000 ether
        uint256 bobBefore = euroToken.balanceOf(bob);
        consortium.claimFor(bob);
        assertEq(euroToken.balanceOf(bob) - bobBefore, 1_000 ether);
    }
}
