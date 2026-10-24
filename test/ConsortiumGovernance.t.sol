// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SixDecimalConsortiumEuro is ERC20 {
    constructor() ERC20("Test Euro", "EURO") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ConsortiumGovernanceTest is ProtocolFixture {
    ConsortiumFactory private factory;
    uint256 private nonce;
    uint256 private constant AUTHORIZER_KEY = 0xC0AA01;
    bytes32 private constant RECEIPT = keccak256("OPERATING_RECEIPT");
    bytes32 private constant EXPENSE = keccak256("OPERATING_EXPENSE");

    function setUp() public override {
        super.setUp();
        factory = _factory(revenue, aerarium);
    }

    function _factory(JuvantiaRevenueDistributor distributor, JuvantiaAerarium budget)
        private
        returns (ConsortiumFactory f)
    {
        f = ConsortiumFactory(
            address(
                new ERC1967Proxy(
                    address(
                        new ConsortiumFactory(
                            address(new Consortium()),
                            address(new JuvantiaAsset()),
                            address(distributor),
                            address(budget)
                        )
                    ),
                    abi.encodeCall(ConsortiumFactory.initialize, (address(this), vm.addr(AUTHORIZER_KEY)))
                )
            )
        );
        distributor.setRegistrar(address(f), true);
    }

    function _voucher(uint256 aliceShares, uint256 bobShares, uint256 petty, uint256 major)
        private
        returns (ConsortiumFactory.ConsortiumDeploymentVoucher memory v)
    {
        address[] memory owners = new address[](2);
        owners[0] = alice;
        owners[1] = bob;
        uint256[] memory balances = new uint256[](2);
        balances[0] = aliceShares;
        balances[1] = bobShares;
        v = ConsortiumFactory.ConsortiumDeploymentVoucher({
            draftId: bytes32(++nonce),
            name: "Governed Consortium",
            symbol: "GOV",
            magister: alice,
            incorporators: owners,
            incorporatorShares: balances,
            treasuryShares: 100_000 ether - aliceShares - bobShares,
            pettyLimit: petty,
            majorLimit: major,
            deadline: block.timestamp + 1 hours,
            salt: bytes32(nonce)
        });
    }

    function _sign(ConsortiumFactory f, ConsortiumFactory.ConsortiumDeploymentVoucher memory v)
        private
        view
        returns (bytes memory)
    {
        (uint8 recovery, bytes32 r, bytes32 s) = vm.sign(AUTHORIZER_KEY, f.hashVoucher(v));
        return abi.encodePacked(r, s, recovery);
    }

    function _create(uint256 aliceShares, uint256 bobShares) private returns (Consortium c, JuvantiaAsset shares) {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v =
            _voucher(aliceShares, bobShares, 1_000 ether, 50_000 ether);
        (address organization, address token) = factory.createConsortium(v, _sign(factory, v));
        vm.roll(block.number + 1);
        return (Consortium(organization), JuvantiaAsset(token));
    }

    function _fund(Consortium c) private {
        c.depositOperating(100_000 ether, keccak256("fund"), RECEIPT);
    }

    function _expense(Consortium c, Consortium.ProposalType kind, uint256 amount) private returns (uint256 id) {
        vm.prank(alice);
        return c.propose(kind, abi.encode(carol, amount, keccak256(abi.encode(kind, amount))), EXPENSE);
    }

    function _executed(Consortium c, uint256 id) private view returns (bool done) {
        (,,,,,, done,) = c.proposals(id);
    }

    function testTransferredSharesCannotVoteTwice() public {
        (Consortium c, JuvantiaAsset shares) = _create(75_000 ether, 25_000 ether);
        vm.startPrank(bob);
        uint256 id = c.propose(Consortium.ProposalType.MagisterElection, abi.encode(bob), bytes32(0));
        c.castVote(id, true);
        shares.transfer(carol, 25_000 ether);
        vm.stopPrank();
        vm.prank(carol);
        vm.expectRevert("No voting weight");
        c.castVote(id, true);
        assertFalse(_executed(c, id));
        assertEq(c.magister(), alice);
        (,,,, uint256 forVotes,,,) = c.proposals(id);
        assertEq(forVotes, 25_000 ether);
    }

    function testSnapshotSupplyDoesNotShrinkWhenOwnersDonateToTreasury() public {
        (Consortium c, JuvantiaAsset shares) = _create(75_000 ether, 25_000 ether);
        vm.startPrank(bob);
        uint256 id = c.propose(Consortium.ProposalType.MagisterElection, abi.encode(bob), bytes32(0));
        c.castVote(id, true);
        vm.stopPrank();
        vm.prank(alice);
        shares.transfer(address(c), 60_000 ether);
        assertEq(c.circulatingSupply(), 40_000 ether);
        assertEq(c.proposalVotingSupply(id), 100_000 ether);
        vm.expectRevert("Threshold not met");
        c.executeProposal(id);
        vm.prank(alice);
        c.castVote(id, true);
        assertEq(c.magister(), bob);
    }

    function testHistoricalTreasurySharesExcludedFromVoting() public {
        (Consortium c,) = _create(60_000 ether, 20_000 ether);
        vm.prank(alice);
        uint256 id = c.propose(Consortium.ProposalType.MagisterElection, abi.encode(bob), bytes32(0));
        assertEq(c.proposalVotingSupply(id), 80_000 ether);
        vm.prank(address(c));
        vm.expectRevert("Treasury cannot vote");
        c.castVote(id, true);
    }

    function testNewlyCreatedSharesNeedACompletedBlockBeforeProposal() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v = _voucher(60_000 ether, 20_000 ether, 1, 100);
        (address organization,) = factory.createConsortium(v, _sign(factory, v));
        vm.prank(alice);
        vm.expectRevert("No circulating shares");
        Consortium(organization).propose(Consortium.ProposalType.MagisterElection, abi.encode(bob), bytes32(0));
    }

    function testPettyExpenseApprovesAtExactlyFiftyPointZeroZeroOnePercent() public {
        (Consortium c,) = _create(50_001 ether, 49_999 ether);
        _fund(c);
        uint256 id = _expense(c, Consortium.ProposalType.PettyExpenditure, 500 ether);
        vm.prank(alice);
        c.castVote(id, true);
        assertTrue(_executed(c, id));
        assertEq(revenue.accountRevenue(carol), 500 ether);
    }

    function testPettyExpenseRejectsOneShareBaseUnitBelowThreshold() public {
        (Consortium c,) = _create(50_001 ether - 1, 49_999 ether + 1);
        _fund(c);
        uint256 id = _expense(c, Consortium.ProposalType.PettyExpenditure, 500 ether);
        vm.prank(alice);
        c.castVote(id, true);
        assertFalse(_executed(c, id));
        assertEq(revenue.accountRevenue(carol), 0);
    }

    function testElectionStillRequiresMoreThanFiftyPointZeroZeroOnePercent() public {
        (Consortium c,) = _create(50_001 ether, 49_999 ether);
        vm.prank(alice);
        uint256 id = c.propose(Consortium.ProposalType.MagisterElection, abi.encode(bob), bytes32(0));
        vm.prank(alice);
        c.castVote(id, true);
        assertFalse(_executed(c, id));
        assertEq(c.magister(), alice);
    }

    function testMajorExpenseApprovesAtExactlySixtyFivePercent() public {
        (Consortium c,) = _create(65_000 ether, 35_000 ether);
        _fund(c);
        uint256 id = _expense(c, Consortium.ProposalType.MajorExpenditure, 2_000 ether);
        vm.prank(alice);
        c.castVote(id, true);
        assertTrue(_executed(c, id));
        assertEq(revenue.accountRevenue(carol), 2_000 ether);
    }

    function testMajorExpenseRejectsOneShareBaseUnitBelowThreshold() public {
        (Consortium c,) = _create(65_000 ether - 1, 35_000 ether + 1);
        _fund(c);
        uint256 id = _expense(c, Consortium.ProposalType.MajorExpenditure, 2_000 ether);
        vm.prank(alice);
        c.castVote(id, true);
        assertFalse(_executed(c, id));
    }

    function testLimitsPackageNeedsSixtyFivePercent() public {
        (Consortium c,) = _create(60_000 ether, 40_000 ether);
        vm.prank(alice);
        uint256 id = c.propose(
            Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(10 ether), uint256(100 ether)), bytes32(0)
        );
        vm.prank(alice);
        c.castVote(id, true);
        assertEq(c.pettyLimit(), 1_000 ether);
        vm.prank(bob);
        c.castVote(id, true);
        assertEq(c.pettyLimit(), 10 ether);
        assertEq(c.majorLimit(), 100 ether);
    }

    function testLimitsPackageApprovesAtExactlySixtyFivePercent() public {
        (Consortium c,) = _create(65_000 ether, 35_000 ether);
        vm.prank(alice);
        uint256 id = c.propose(
            Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(10 ether), uint256(100 ether)), bytes32(0)
        );
        vm.prank(alice);
        c.castVote(id, true);
        assertTrue(_executed(c, id));
        assertEq(c.pettyLimit(), 10 ether);
    }

    function testPackageProposerNeedsFivePercentUnlessMagister() public {
        (Consortium c,) = _create(96_000 ether, 4_000 ether);
        vm.prank(bob);
        vm.expectRevert("Must hold >= 5% circulating shares");
        c.propose(
            Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(10 ether), uint256(100 ether)), bytes32(0)
        );
        (Consortium second,) = _create(0, 100_000 ether);
        vm.prank(alice);
        uint256 id = second.propose(
            Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(10 ether), uint256(100 ether)), bytes32(0)
        );
        vm.prank(bob);
        second.castVote(id, true);
        assertTrue(_executed(second, id));
    }

    function testChangingLimitsCannotDowngradeAnOpenMajorExpenseVote() public {
        (Consortium c,) = _create(60_000 ether, 40_000 ether);
        _fund(c);
        uint256 expenseId = _expense(c, Consortium.ProposalType.MajorExpenditure, 20_000 ether);
        vm.prank(alice);
        uint256 limitsId = c.propose(
            Consortium.ProposalType.SpendingLimitsPackage,
            abi.encode(uint256(30_000 ether), uint256(100_000 ether)),
            bytes32(0)
        );
        vm.prank(alice);
        c.castVote(limitsId, true);
        vm.prank(bob);
        c.castVote(limitsId, true);
        assertEq(c.pettyLimit(), 30_000 ether);
        vm.prank(alice);
        c.castVote(expenseId, true);
        assertFalse(_executed(c, expenseId));
        vm.prank(bob);
        c.castVote(expenseId, true);
        assertTrue(_executed(c, expenseId));
    }

    function testExpenseCapIsFrozenWithTheProposal() public {
        (Consortium c,) = _create(65_000 ether, 35_000 ether);
        _fund(c);
        uint256 expenseId = _expense(c, Consortium.ProposalType.MajorExpenditure, 20_000 ether);
        vm.prank(alice);
        uint256 limitsId = c.propose(
            Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(10 ether), uint256(100 ether)), bytes32(0)
        );
        vm.prank(alice);
        c.castVote(limitsId, true);
        assertEq(c.majorLimit(), 100 ether);
        assertEq(c.proposalExpenseCap(expenseId), 50_000 ether);
        vm.prank(alice);
        c.castVote(expenseId, true);
        assertTrue(_executed(c, expenseId));
    }

    function testExpenseCannotSelectTheWrongApprovalTierOrExceedItsCap() public {
        (Consortium c,) = _create(65_000 ether, 35_000 ether);
        vm.startPrank(alice);
        vm.expectRevert("Exceeds expense limit");
        c.propose(
            Consortium.ProposalType.PettyExpenditure,
            abi.encode(carol, uint256(2_000 ether), keccak256("petty")),
            EXPENSE
        );
        vm.expectRevert("Use petty proposal");
        c.propose(
            Consortium.ProposalType.MajorExpenditure, abi.encode(carol, uint256(500 ether), keccak256("major")), EXPENSE
        );
        vm.expectRevert("Exceeds expense limit");
        c.propose(
            Consortium.ProposalType.MajorExpenditure,
            abi.encode(carol, uint256(50_001 ether), keccak256("cap")),
            EXPENSE
        );
        vm.stopPrank();
    }

    function testExpiredExpenseCannotCollectVotesOrExecute() public {
        (Consortium c,) = _create(65_000 ether, 35_000 ether);
        uint256 id = _expense(c, Consortium.ProposalType.MajorExpenditure, 2_000 ether);
        vm.warp(block.timestamp + 36 hours + 1);
        vm.prank(alice);
        vm.expectRevert("Voting closed");
        c.castVote(id, true);
        vm.expectRevert("Proposal expired");
        c.executeProposal(id);
    }

    function testSignedCreationVoucherBindsBothInitialLimits() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v = _voucher(60_000 ether, 20_000 ether, 11, 222);
        bytes memory signature = _sign(factory, v);
        v.pettyLimit = 12;
        vm.expectRevert("Invalid voucher signature");
        factory.createConsortium(v, signature);
        v.pettyLimit = 11;
        v.majorLimit = 223;
        vm.expectRevert("Invalid voucher signature");
        factory.createConsortium(v, signature);
    }

    function testInvalidCreationAndReplacementPackagesRejected() public {
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v = _voucher(60_000 ether, 20_000 ether, 0, 100);
        bytes memory signature = _sign(factory, v);
        vm.expectRevert("Invalid spending limits");
        factory.createConsortium(v, signature);
        (Consortium c,) = _create(65_000 ether, 35_000 ether);
        vm.prank(alice);
        vm.expectRevert("Invalid spending limits");
        c.propose(Consortium.ProposalType.SpendingLimitsPackage, abi.encode(uint256(200), uint256(100)), bytes32(0));
    }

    function testOwnerConfiguredSixDecimalLimitsUseExactBaseUnits() public {
        SixDecimalConsortiumEuro token = new SixDecimalConsortiumEuro();
        JuvantiaAerarium budget = new JuvantiaAerarium(address(token), address(this));
        JuvantiaRevenueDistributor distributor =
            new JuvantiaRevenueDistributor(address(token), address(this), address(budget));
        JuvantiaPaymentRegistry rules = new JuvantiaPaymentRegistry(address(this));
        distributor.setPaymentRegistry(address(rules));
        budget.configureSettlement(address(rules), address(distributor));
        rules.publish(RECEIPT, JuvantiaPaymentRegistry.Rule(true, true, 1, 0, 0));
        rules.publish(EXPENSE, JuvantiaPaymentRegistry.Rule(true, true, 1, 0, 0));
        ConsortiumFactory f = _factory(distributor, budget);
        ConsortiumFactory.ConsortiumDeploymentVoucher memory v = _voucher(65_000 ether, 35_000 ether, 10e6, 100e6);
        (address organization,) = f.createConsortium(v, _sign(f, v));
        vm.roll(block.number + 1);
        Consortium c = Consortium(organization);
        assertEq(c.pettyLimit(), 10e6);
        assertEq(c.majorLimit(), 100e6);
        token.mint(address(this), 100e6);
        token.approve(address(distributor), 100e6);
        c.depositOperating(100e6, keccak256("six-decimal-funding"), RECEIPT);
        uint256 id = _expense(c, Consortium.ProposalType.MajorExpenditure, 20e6);
        vm.prank(alice);
        c.castVote(id, true);
        assertEq(distributor.accountRevenue(carol), 20e6);
        assertEq(c.operatingBalance(), 80e6);
    }
}
