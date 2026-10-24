// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract JudicialWalletFixture {}

contract JudicialCustodyTest is ProtocolFixture {
    JuvantiaTradeHub internal trade;

    function setUp() public override {
        super.setUp();
        trade = JuvantiaTradeHub(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaTradeHub()),
                    abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue)))
                )
            )
        );
        revenue.setEscrow(address(trade), true);
        revenue.setPaymentSource(address(trade), 1);
        revenue.setTribunal(address(this));
        asset.setTribunal(address(this));
    }

    function _list(address seller, uint256 amount, uint256 price) internal returns (uint256 id) {
        vm.startPrank(seller);
        asset.approve(address(trade), amount);
        id = trade.createOrder(address(asset), amount, price, keccak256("SHARE_TRADE"));
        vm.stopPrank();
    }

    function testJudicialTransferCannotDuplicateEscrowOwnershipOrConsumeOtherCredits() public {
        uint256 id = _list(alice, 100_000 ether, 1 ether);
        vm.expectRevert("Escrow custody protected");
        asset.judicialTransfer(address(trade), bob, 100_000 ether);
        assertEq(revenue.effectiveBalanceOf(address(asset), alice), 100_000 ether);
        assertEq(revenue.effectiveBalanceOf(address(asset), bob), 0);

        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("unrelated"), 100 ether, 0, carol);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        assertEq(revenue.claimFor(address(asset), alice), 100 ether);
        assertEq(revenue.claimFor(address(asset), bob), 0);
        assertEq(revenue.claimAccountFor(carol), 100 ether);
        assertEq(revenue.totalClaimed(address(asset)), revenue.totalDistributed(address(asset)));
        assertEq(euroToken.balanceOf(address(revenue)), 0);

        vm.prank(alice);
        trade.cancelOrder(id);
        assertEq(asset.balanceOf(alice), 100_000 ether);
    }

    function testRevokingEscrowCannotEnableSeizureOrStrandCancellation() public {
        uint256 id = _list(alice, 100 ether, 1 ether);
        revenue.setEscrow(address(trade), false);
        vm.expectRevert("Escrow custody protected");
        asset.judicialSeize(address(trade), bob, 1 ether);
        vm.prank(alice);
        trade.cancelOrder(id);
        assertEq(asset.balanceOf(alice), 100_000 ether);
    }

    function testDirectSeizureFromSmartWalletPreservesItsAlreadyEarnedEuro() public {
        address wallet = address(new JudicialWalletFixture());
        vm.prank(alice);
        asset.transfer(wallet, 40_000 ether);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        uint256 beforeSeizure = block.number;
        vm.roll(block.number + 1);
        asset.judicialTransfer(wallet, bob, 10_000 ether);
        assertEq(revenue.claimable(address(asset), wallet), 40 ether);
        assertEq(revenue.claimable(address(asset), bob), 0);
        assertEq(asset.getPastBalance(wallet, beforeSeizure), 40_000 ether);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        assertEq(revenue.claimFor(address(asset), wallet), 70 ether);
        assertEq(revenue.claimFor(address(asset), bob), 10 ether);
        assertEq(revenue.claimFor(address(asset), alice), 120 ether);
        assertEq(asset.totalSupply(), 100_000 ether);
    }

    function testFineDebitsOnlyTheDebtorsTradeEuroAndLeavesListedShares() public {
        vm.prank(alice);
        asset.transfer(carol, 100 ether);
        uint256 aliceOrder = _list(alice, 1_000 ether, 1 ether);
        uint256 carolOrder = _list(carol, 100 ether, 2 ether);
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 300 ether);
        trade.fillOrder(aliceOrder, 100 ether);
        trade.fillOrder(carolOrder, 100 ether);
        vm.stopPrank();
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        uint256 earnings = revenue.claimable(address(asset), alice) - 100 ether;

        vm.prank(bob);
        vm.expectRevert("Only tribunal");
        revenue.judicialClaimTrade(address(asset), alice, bob, 10 ether);
        vm.expectRevert("Insufficient trade proceeds");
        revenue.judicialClaimTrade(address(asset), alice, bob, 101 ether);
        uint256 recipientBefore = euroToken.balanceOf(bob);
        revenue.judicialClaimTrade(address(asset), alice, bob, 10 ether);

        assertEq(euroToken.balanceOf(bob), recipientBefore + 10 ether);
        assertEq(revenue.tradeProceeds(address(asset), alice), 90 ether);
        assertEq(revenue.pendingTradeProceeds(alice), 90 ether);
        assertEq(revenue.tradeProceeds(address(asset), carol), 200 ether);
        assertEq(revenue.claimable(address(asset), alice), earnings + 90 ether);
        assertEq(revenue.totalTradeClaimed(address(asset)), 10 ether);
        assertEq(revenue.totalClaimed(address(asset)), 0);
        assertEq(revenue.escrowedFor(address(asset), alice), 900 ether);
        vm.prank(alice);
        trade.cancelOrder(aliceOrder);
        assertEq(revenue.escrowedFor(address(asset), alice), 0);
    }

    function testFuzzJudicialCustodyPreservesPoolAccountAndTradeSolvency(
        uint96 listedSeed,
        uint96 filledSeed,
        uint96 fineSeed
    ) public {
        uint256 listed = bound(uint256(listedSeed), 1, 1_000 ether);
        uint256 filled = bound(uint256(filledSeed), 1, listed);
        uint256 fine = bound(uint256(fineSeed), 1, filled);
        uint256 id = _list(alice, listed, 1 ether);
        vm.startPrank(bob);
        euroToken.approve(address(revenue), filled);
        trade.fillOrder(id, filled);
        vm.stopPrank();

        if (filled != listed) {
            vm.expectRevert("Escrow custody protected");
            asset.judicialSeize(address(trade), bob, 1);
        }
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("separate-credit"), 100 ether, 0, carol);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        revenue.judicialClaimTrade(address(asset), alice, carol, fine);
        assertEq(revenue.claimAccountFor(carol), 100 ether);
        revenue.claimFor(address(asset), alice);
        revenue.claimFor(address(asset), bob);
        assertLe(revenue.totalClaimed(address(asset)), 100 ether);
        assertEq(revenue.totalTradeClaimed(address(asset)), filled);
        assertEq(revenue.pendingTradeProceeds(alice), 0);
        assertLe(euroToken.balanceOf(address(revenue)), 1); // At most one indivisible pool unit.
        if (filled != listed) {
            vm.prank(alice);
            trade.cancelOrder(id);
        }
        assertEq(asset.balanceOf(alice) + asset.balanceOf(bob), 100_000 ether);
        assertEq(asset.balanceOf(address(trade)), 0);
    }

    function testOwnershipHistoryUsesCompletedBlockBalancesWithoutDelegation() public {
        uint256 initialBlock = block.number;
        vm.roll(initialBlock + 1);
        assertEq(asset.getPastBalance(alice, initialBlock), 100_000 ether);
        vm.prank(alice);
        asset.transfer(bob, 20_000 ether);
        vm.prank(bob);
        asset.transfer(carol, 10_000 ether);
        vm.prank(alice);
        asset.transfer(alice, 1 ether);
        vm.roll(initialBlock + 2);
        assertEq(asset.getPastBalance(alice, initialBlock), 100_000 ether);
        assertEq(asset.getPastBalance(alice, initialBlock + 1), 80_000 ether);
        assertEq(asset.getPastBalance(bob, initialBlock + 1), 10_000 ether);
        assertEq(asset.getPastBalance(carol, initialBlock + 1), 10_000 ether);
        assertEq(asset.getPastTotalSupply(initialBlock + 1), 100_000 ether);
        vm.expectRevert("Snapshot block not completed");
        asset.getPastBalance(alice, block.number);
        vm.expectRevert("Snapshot block not completed");
        asset.getPastTotalSupply(block.number + 1);
    }
}
