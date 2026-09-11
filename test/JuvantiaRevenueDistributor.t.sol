// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";

contract JuvantiaRevenueDistributorTest is ProtocolFixture {
    function testSellerKeepsRevenueAccruedBeforeTransfer() public {
        revenue.distributeRevenue(address(asset), 100 ether);
        vm.prank(alice);
        asset.transfer(bob, 100_000 ether);
        assertEq(revenue.claimFor(address(asset), bob), 0);
        assertEq(revenue.claimFor(address(asset), alice), 100 ether);
        assertEq(revenue.claimFor(address(asset), alice), 0);
        revenue.distributeRevenue(address(asset), 200 ether);
        assertEq(revenue.claimFor(address(asset), alice), 0);
        assertEq(revenue.claimFor(address(asset), bob), 200 ether);
    }

    function testPartialTransferAndMultipleDistributions() public {
        revenue.distributeRevenue(address(asset), 100 ether);
        vm.prank(alice);
        asset.transfer(bob, 20_000 ether);
        revenue.distributeRevenue(address(asset), 1_000 ether);
        vm.prank(bob);
        asset.transfer(carol, 10_000 ether);
        revenue.distributeRevenue(address(asset), 100 ether);
        assertEq(revenue.claimFor(address(asset), alice), 980 ether);
        assertEq(revenue.claimFor(address(asset), bob), 210 ether);
        assertEq(revenue.claimFor(address(asset), carol), 10 ether);
        assertEq(revenue.totalClaimed(address(asset)), 1_200 ether);
    }

    function testTransferFromAlsoCheckpoints() public {
        revenue.distributeRevenue(address(asset), 5 ether);
        vm.prank(alice);
        asset.approve(bob, 100_000 ether);
        vm.prank(bob);
        asset.transferFrom(alice, carol, 100_000 ether);
        assertEq(revenue.claimFor(address(asset), carol), 0);
        assertEq(revenue.claimFor(address(asset), alice), 5 ether);
    }

    function testZeroAndSelfTransferCannotResetEarnings() public {
        revenue.distributeRevenue(address(asset), 5 ether);
        vm.startPrank(alice);
        asset.transfer(alice, 1 ether);
        asset.transfer(bob, 0);
        vm.stopPrank();
        assertEq(revenue.claimFor(address(asset), alice), 5 ether);
        assertEq(revenue.claimFor(address(asset), bob), 0);
    }

    function testFractionsSurviveCheckpoints() public {
        vm.prank(alice);
        asset.transfer(bob, 50_000 ether);
        revenue.distributeRevenue(address(asset), 1);
        assertEq(revenue.claimFor(address(asset), bob), 0);
        vm.prank(bob);
        asset.transfer(bob, 1);
        revenue.distributeRevenue(address(asset), 1);
        assertEq(revenue.claimFor(address(asset), bob), 1);
        assertEq(revenue.claimFor(address(asset), alice), 1);
    }

    function testUnknownAssetsAndForgedHooksRejected() public {
        vm.expectRevert("Unknown asset");
        revenue.distributeRevenue(address(euroToken), 1 ether);
        vm.expectRevert("Unknown asset");
        revenue.checkpointTransfer(alice, bob);
        vm.prank(bob);
        vm.expectRevert("Not registrar");
        revenue.registerAsset(address(euroToken));
    }

    function testClaimBatchPaysCallerOnlyOnce() public {
        revenue.distributeRevenue(address(asset), 7 ether);
        address[] memory assets = new address[](2);
        assets[0] = address(asset);
        assets[1] = address(asset);
        vm.prank(alice);
        assertEq(revenue.claimBatch(assets), 7 ether);
    }

    function testFuzzRevenueConservedAcrossTransfer(uint96 deposit, uint96 moved) public {
        uint256 amount = bound(uint256(deposit), 1, 100_000 ether);
        uint256 shares = bound(uint256(moved), 0, 100_000 ether);
        revenue.distributeRevenue(address(asset), amount);
        vm.prank(alice);
        asset.transfer(bob, shares);
        assertEq(revenue.claimFor(address(asset), bob), 0);
        assertEq(revenue.claimFor(address(asset), alice), amount);
        revenue.distributeRevenue(address(asset), amount);
        uint256 paid = revenue.claimFor(address(asset), alice) + revenue.claimFor(address(asset), bob);
        assertLe(paid, amount);
        assertLe(amount - paid, 1);
        assertLe(revenue.totalClaimed(address(asset)), revenue.totalDistributed(address(asset)));
    }
}
