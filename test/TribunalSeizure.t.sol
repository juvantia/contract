// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {Syndicate} from "../src/community/Syndicate.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";

contract TribunalSeizureTest is ProtocolFixture {
    address internal tribunal = address(0x791B); // Tribunal smart contract or wallet
    address internal victim = address(0x01C713);
    ConsortiumFactory internal cFactory;
    SyndicateFactory internal sFactory;
    uint256 internal authorizerPk = 0xA117;
    address internal authorizer;

    function setUp() public override {
        super.setUp();
        authorizer = vm.addr(authorizerPk);

        // Deploy Consortium Factory
        Consortium cImpl = new Consortium();
        JuvantiaAsset aImpl = new JuvantiaAsset();
        ConsortiumFactory cfImpl = new ConsortiumFactory(
            address(cImpl),
            address(aImpl),
            address(revenue),
            address(aerarium)
        );
        cFactory = ConsortiumFactory(address(new ERC1967Proxy(
            address(cfImpl),
            abi.encodeCall(ConsortiumFactory.initialize, (address(this), authorizer))
        )));
        revenue.setRegistrar(address(cFactory), true);

        // Deploy Syndicate Factory
        Syndicate sImpl = new Syndicate();
        SyndicateFactory sfImpl = new SyndicateFactory(address(sImpl), address(euroToken));
        sFactory = SyndicateFactory(address(new ERC1967Proxy(
            address(sfImpl),
            abi.encodeCall(SyndicateFactory.initialize, (address(this), authorizer))
        )));
    }

    // ==========================================
    // 1. APU Seizure from Physical Persons
    // ==========================================

    function testPhysicalPersonApuSeizureByTribunal() public {
        // Alice initially has 100,000 APU
        assertEq(asset.balanceOf(alice), 100_000 ether);

        // Non-tribunal cannot seize
        vm.prank(bob);
        vm.expectRevert("Only tribunal");
        asset.judicialTransfer(alice, victim, 10_000 ether);

        // Owner sets tribunal
        asset.setTribunal(tribunal);
        assertEq(asset.tribunal(), tribunal);

        // Tribunal executes judicialTransfer
        vm.prank(tribunal);
        asset.judicialTransfer(alice, victim, 25_000 ether);

        assertEq(asset.balanceOf(alice), 75_000 ether);
        assertEq(asset.balanceOf(victim), 25_000 ether);

        // Revenue checkpoints update correctly: distribute 100 EUR
        revenue.distributeRevenue(address(asset), 100 ether);
        assertEq(revenue.claimable(address(asset), alice), 75 ether);
        assertEq(revenue.claimable(address(asset), victim), 25 ether);

        // Alias judicialSeize also works
        vm.prank(tribunal);
        asset.judicialSeize(alice, victim, 5_000 ether);
        assertEq(asset.balanceOf(alice), 70_000 ether);
        assertEq(asset.balanceOf(victim), 30_000 ether);
    }

    function testUnauthorizedTribunalSetterReverts() public {
        vm.prank(bob);
        vm.expectRevert();
        asset.setTribunal(bob);
    }

    // ==========================================
    // 2. Consortium: EURO & APU Seizure
    // ==========================================

    function testConsortiumEuroAndApuSeizureByTribunal() public {
        cFactory.setTribunal(tribunal);

        // Create a consortium
        address[] memory founders = new address[](1);
        founders[0] = alice;
        uint256[] memory founderShares = new uint256[](1);
        founderShares[0] = 80_000 ether;

        ConsortiumFactory.ConsortiumDeploymentVoucher memory voucher = ConsortiumFactory.ConsortiumDeploymentVoucher({
            draftId: keccak256("draft-c-1"),
            name: "Alpha Corp",
            symbol: "ALP",
            magister: alice,
            founders: founders,
            founderShares: founderShares,
            treasuryShares: 20_000 ether,
            deadline: block.timestamp + 1 hours,
            salt: keccak256("salt-c-1")
        });

        bytes32 digest = cFactory.hashVoucher(voucher);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        (address cClone, address aClone) = cFactory.createConsortium(voucher, signature);
        Consortium consortium = Consortium(cClone);
        JuvantiaAsset shareAsset = JuvantiaAsset(aClone);

        // Check tribunal propagated
        assertEq(consortium.tribunal(), tribunal);
        assertEq(shareAsset.tribunal(), tribunal);

        // Deposit operating EURO into Consortium
        euroToken.mint(address(this), 10_000 ether);
        euroToken.approve(address(consortium), 10_000 ether);
        consortium.depositOperating(10_000 ether, keccak256("ops-1"));
        assertEq(consortium.operatingBalance(), 10_000 ether);

        // Non-tribunal cannot seize EURO
        vm.prank(bob);
        vm.expectRevert("Only tribunal");
        consortium.judicialSeizePayment(victim, 1_000 ether);

        // Tribunal seizes EURO from Consortium
        vm.prank(tribunal);
        consortium.judicialSeizePayment(victim, 3_000 ether);

        assertEq(euroToken.balanceOf(victim), 3_000 ether);
        assertEq(consortium.operatingBalance(), 7_000 ether);

        // Non-tribunal cannot seize shares
        vm.prank(bob);
        vm.expectRevert("Only tribunal");
        consortium.judicialSeizeShares(victim, 5_000 ether);

        // Tribunal seizes treasury shares from Consortium
        assertEq(consortium.treasuryShares(), 20_000 ether);
        vm.prank(tribunal);
        consortium.judicialSeizeShares(victim, 5_000 ether);

        assertEq(shareAsset.balanceOf(victim), 5_000 ether);
        assertEq(consortium.treasuryShares(), 15_000 ether);

        // Tribunal seizes external APU token (the city physical asset)
        asset.setTribunal(tribunal);
        vm.prank(tribunal);
        asset.judicialTransfer(alice, address(consortium), 2_000 ether);
        assertEq(asset.balanceOf(address(consortium)), 2_000 ether);

        vm.prank(tribunal);
        consortium.judicialSeizeToken(address(asset), victim, 1_500 ether);
        assertEq(asset.balanceOf(victim), 1_500 ether);
        assertEq(asset.balanceOf(address(consortium)), 500 ether);
    }

    // ==========================================
    // 3. Syndicate: EURO & APU Seizure
    // ==========================================

    function testSyndicateEuroAndApuSeizureByTribunal() public {
        sFactory.setTribunal(tribunal);

        address[] memory members = new address[](1);
        members[0] = bob;
        uint8[] memory grades = new uint8[](1);
        grades[0] = 3;

        SyndicateFactory.SyndicateDeploymentVoucher memory voucher = SyndicateFactory.SyndicateDeploymentVoucher({
            draftId: keccak256("draft-s-1"),
            name: "Legion Syndicate",
            primus: alice,
            presetType: 0,
            gradeCount: 6,
            members: members,
            memberGrades: grades,
            deadline: block.timestamp + 1 hours,
            salt: keccak256("salt-s-1")
        });

        bytes32 digest = sFactory.hashVoucher(voucher);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(authorizerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        address sClone = sFactory.createSyndicate(voucher, signature);
        Syndicate syndicate = Syndicate(sClone);

        assertEq(syndicate.tribunal(), tribunal);

        // Fund syndicate operating
        euroToken.mint(address(this), 5_000 ether);
        euroToken.approve(address(syndicate), 5_000 ether);
        syndicate.depositOperating(5_000 ether, keccak256("clan-ops"));
        assertEq(syndicate.operatingBalance(), 5_000 ether);

        // Non-tribunal cannot seize
        vm.prank(bob);
        vm.expectRevert("Only tribunal");
        syndicate.judicialSeizePayment(victim, 1_000 ether);

        // Tribunal seizes EURO
        vm.prank(tribunal);
        syndicate.judicialSeizePayment(victim, 2_000 ether);
        assertEq(euroToken.balanceOf(victim), 2_000 ether);
        assertEq(syndicate.operatingBalance(), 3_000 ether);

        // Transfer some APU to syndicate
        asset.setTribunal(tribunal);
        vm.prank(tribunal);
        asset.judicialTransfer(alice, address(syndicate), 4_000 ether);
        assertEq(asset.balanceOf(address(syndicate)), 4_000 ether);

        // Tribunal seizes APU from Syndicate using judicialSeizeToken
        vm.prank(tribunal);
        syndicate.judicialSeizeToken(address(asset), victim, 3_000 ether);
        assertEq(asset.balanceOf(victim), 3_000 ether);
        assertEq(asset.balanceOf(address(syndicate)), 1_000 ether);
    }
}
