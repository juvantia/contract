// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ConsortiumFactoryTest is ProtocolFixture {
    ConsortiumFactory internal factory;
    Consortium internal consortiumImpl;
    JuvantiaAsset internal assetImpl;

    uint256 internal authorizerPrivateKey = 0xA11CE_516;
    address internal authorizer;

    function testOwnerAllocationRequiresVoteThreshold() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(keccak256("allocation-threshold"));
        (address cClone, address token) = factory.createConsortium(voucher, _signVoucher(voucher));
        Consortium consortium = Consortium(cClone);
        euroToken.approve(cClone, 1_000 ether);
        consortium.depositOperating(1_000 ether, keccak256("operating-funds"));
        vm.prank(bob);
        uint256 proposal = consortium.propose(Consortium.ProposalType.RevenueDistribution, abi.encode(800 ether));
        vm.prank(bob);
        consortium.castVote(proposal, true);
        assertEq(consortium.distributablePool(), 0);
        assertEq(consortium.operatingBalance(), 1_000 ether);
        assertEq(revenue.claimable(token, alice), 0);
        vm.prank(alice);
        consortium.castVote(proposal, true);
        assertEq(consortium.operatingBalance(), 200 ether);
        assertEq(consortium.distributablePool(), 800 ether);
        assertEq(revenue.claimFor(token, alice), 600 ether);
        assertEq(revenue.claimFor(token, bob), 200 ether);
    }

    function testFundingFailureRollsBackVoteAndCanBeRetried() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(keccak256("allocation-retry"));
        (address cClone,) = factory.createConsortium(voucher, _signVoucher(voucher));
        Consortium consortium = Consortium(cClone);
        euroToken.approve(cClone, 1_000 ether);
        consortium.depositOperating(1_000 ether, keccak256("operating-funds"));
        vm.prank(alice);
        uint256 proposal = consortium.propose(Consortium.ProposalType.RevenueDistribution, abi.encode(800 ether));
        vm.mockCall(
            address(euroToken),
            abi.encodeCall(IERC20.transferFrom, (cClone, address(revenue), 800 ether)),
            abi.encode(true)
        );
        vm.prank(alice);
        vm.expectRevert("Incorrect deposit");
        consortium.castVote(proposal, true);
        assertFalse(consortium.hasVoted(proposal, alice));
        (,,,, uint256 forVotes,, bool executed,) = consortium.proposals(proposal);
        assertEq(forVotes, 0);
        assertFalse(executed);
        assertEq(consortium.totalAllocated(), 0);
        assertEq(consortium.operatingBalance(), 1_000 ether);
        vm.clearMockedCalls();
        vm.prank(alice);
        consortium.castVote(proposal, true);
        assertEq(consortium.distributablePool(), 800 ether);
    }

    function testOperatingSeizureCannotTouchOwnersReserve() public {
        factory.setTribunal(address(this));
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(keccak256("separate-reserve"));
        (address cClone, address token) = factory.createConsortium(voucher, _signVoucher(voucher));
        Consortium consortium = Consortium(cClone);
        euroToken.approve(cClone, 1_000 ether);
        consortium.depositOperating(1_000 ether, keccak256("operating-funds"));
        vm.prank(alice);
        uint256 proposal = consortium.propose(Consortium.ProposalType.RevenueDistribution, abi.encode(800 ether));
        vm.prank(alice);
        consortium.castVote(proposal, true);
        vm.expectRevert("Insufficient balance");
        consortium.judicialSeizePayment(carol, 201 ether);
        vm.expectRevert("Insufficient balance");
        consortium.judicialSeizeToken(address(euroToken), carol, 201 ether);
        consortium.judicialSeizePayment(carol, 200 ether);
        assertEq(consortium.operatingBalance(), 0);
        assertEq(consortium.distributablePool(), 800 ether);
        assertEq(revenue.claimFor(token, alice), 600 ether);
        assertEq(revenue.claimFor(token, bob), 200 ether);
        assertEq(consortium.distributablePool(), 0);
    }

    function setUp() public override {
        super.setUp();
        authorizer = vm.addr(authorizerPrivateKey);

        consortiumImpl = new Consortium();
        assetImpl = new JuvantiaAsset();

        ConsortiumFactory factoryImpl =
            new ConsortiumFactory(address(consortiumImpl), address(assetImpl), address(revenue), address(aerarium));

        factory = ConsortiumFactory(
            address(
                new ERC1967Proxy(
                    address(factoryImpl), abi.encodeCall(ConsortiumFactory.initialize, (address(this), authorizer))
                )
            )
        );

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
        address[] memory incorporators = new address[](2);
        incorporators[0] = alice;
        incorporators[1] = bob;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 60_000 ether;
        shares[1] = 20_000 ether;

        voucher = ConsortiumFactory.ConsortiumDeploymentVoucher({
            draftId: draftId,
            name: "RoboCorp Consortium",
            symbol: "ROBO",
            magister: alice,
            incorporators: incorporators,
            incorporatorShares: shares,
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
        Consortium(cClone).initialize(address(euroToken), aClone, address(revenue), bob, address(this));
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
        uint256 pId = consortium.propose(Consortium.ProposalType.MagisterElection, abi.encode(bob));

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
        uint256 pId = consortium.propose(Consortium.ProposalType.RevenueDistribution, abi.encode(4_000 ether));

        // Alice votes support (60k / 80k = 75% >= 75%) -> auto-executes!
        vm.prank(alice);
        consortium.castVote(pId, true);

        assertEq(consortium.distributablePool(), 4_000 ether);
        assertEq(consortium.operatingBalance(), 6_000 ether);
        assertEq(euroToken.balanceOf(cClone), 6_000 ether);
        assertEq(euroToken.balanceOf(address(revenue)), 4_000 ether);

        // Alice (60k/80k = 75%) claims 3,000 ether
        uint256 aliceBefore = euroToken.balanceOf(alice);
        revenue.claimFor(address(consortium.shareToken()), alice);
        assertEq(euroToken.balanceOf(alice) - aliceBefore, 3_000 ether);

        // Bob (20k/80k = 25%) claims 1,000 ether
        uint256 bobBefore = euroToken.balanceOf(bob);
        revenue.claimFor(address(consortium.shareToken()), bob);
        assertEq(euroToken.balanceOf(bob) - bobBefore, 1_000 ether);
    }

    function testConsortiumSpendingLimitsPackageTwoTiers() public {
        bytes32 draftId = keccak256("draft-limits-2tier");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone,) = factory.createConsortium(voucher, sig);
        Consortium consortium = Consortium(cClone);

        assertEq(consortium.pettyLimit(), 1_000 ether);
        assertEq(consortium.majorLimit(), 50_000 ether);

        // Alice proposes new limits: petty = 2,500 ether, major = 75,000 ether
        vm.prank(alice);
        uint256 pId = consortium.propose(
            Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(2_500 ether), uint256(75_000 ether))
        );

        // Alice votes support (60k / 80k = 75% > 50.001%) -> auto-executes
        vm.prank(alice);
        consortium.castVote(pId, true);

        assertEq(consortium.pettyLimit(), 2_500 ether);
        assertEq(consortium.majorLimit(), 75_000 ether);
    }

    function testConsortiumMajorExpenditureProposal() public {
        bytes32 draftId = keccak256("draft-major-exp");
        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = _buildVoucher(draftId);
        bytes memory sig = _signVoucher(voucher);

        (address cClone,) = factory.createConsortium(voucher, sig);
        Consortium consortium = Consortium(cClone);

        euroToken.approve(cClone, 30_000 ether);
        consortium.depositOperating(30_000 ether, keccak256("dep-ops"));

        // Alice proposes major spending of 20,000 ether to Carol
        vm.prank(alice);
        uint256 pId = consortium.propose(
            Consortium.ProposalType.MajorExpenditure, abi.encode(carol, uint256(20_000 ether), keccak256("major-ref-1"))
        );

        // Alice votes support -> auto-executes
        vm.prank(alice);
        consortium.castVote(pId, true);

        assertEq(euroToken.balanceOf(carol), 20_000 ether);
        assertEq(consortium.operatingBalance(), 10_000 ether);
    }
}
