// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";

contract JuvantiaPaymentsTest is ProtocolFixture {
    function testServiceReceiptHasAllBusinessIdentifiers() public {
        bytes32 requestId = keccak256("service-request");
        uint256 amount = 12 ether + 123456789012345678;
        vm.startPrank(alice);
        eure.approve(address(services), amount);
        vm.expectEmit(true, true, true, true, address(services));
        emit JuvantiaServicePayments.ServicePaid(requestId, alice, carol, amount);
        services.pay(requestId, carol, amount);
        assertEq(eure.balanceOf(carol), amount);
        vm.expectRevert("Already paid");
        services.pay(requestId, carol, amount);
        vm.stopPrank();
    }

    function testAnotherPayerCannotConsumeRequest() public {
        bytes32 requestId = keccak256("shared-request");
        vm.startPrank(bob);
        eure.approve(address(services), 1 ether);
        services.pay(requestId, carol, 1 ether);
        vm.stopPrank();
        vm.startPrank(alice);
        eure.approve(address(services), 10 ether);
        services.pay(requestId, carol, 10 ether);
        vm.stopPrank();
        assertTrue(services.paid(alice, requestId));
        assertEq(eure.balanceOf(carol), 11 ether);
    }

    function testRevertedTransferDoesNotConsumeRequest() public {
        vm.startPrank(alice);
        vm.expectRevert();
        services.pay(bytes32(uint256(1)), carol, 1 ether);
        vm.stopPrank();
        assertFalse(services.paid(alice, bytes32(uint256(1))));
    }

    function testLeaseTaxAndRevenueAtomic() public {
        vm.startPrank(bob);
        eure.approve(address(leasing), 100 ether);
        leasing.processLeasePayment(address(asset), 100 ether, keccak256("lease-1"));
        vm.stopPrank();
        assertEq(eure.balanceOf(address(aerarium)), 10 ether);
        assertEq(aerarium.totalCollected(), 10 ether);
        assertEq(revenue.claimable(address(asset), alice), 90 ether);
        assertEq(eure.balanceOf(address(leasing)), 0);
        assertEq(eure.allowance(address(leasing), address(aerarium)), 0);
        assertEq(eure.allowance(address(leasing), address(revenue)), 0);
    }

    function testUnknownLeaseAssetDoesNotTakeMoney() public {
        vm.startPrank(bob);
        eure.approve(address(leasing), 100 ether);
        vm.expectRevert("Unknown asset");
        leasing.processLeasePayment(address(eure), 100 ether, keccak256("lease-2"));
        vm.stopPrank();
        assertEq(eure.balanceOf(bob), 1_000 ether);
    }

    function testTaxAndTreasuryRequireAdmin() public {
        vm.startPrank(bob);
        vm.expectRevert();
        leasing.setTaxBps(0);
        vm.expectRevert();
        aerarium.spend(bob, 1 ether, "unauthorized");
        vm.stopPrank();
        vm.expectRevert("Invalid tax");
        leasing.setTaxBps(10_001);
    }

    function testTreasurySpending() public {
        eure.approve(address(aerarium), 20 ether);
        aerarium.receiveTax(20 ether, "registration");
        aerarium.spend(carol, 12 ether, "equipment");
        assertEq(aerarium.totalSpent(), 12 ether);
        assertEq(eure.balanceOf(carol), 12 ether);
        assertEq(eure.balanceOf(address(aerarium)), 8 ether);
    }
}
