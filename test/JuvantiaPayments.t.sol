// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";

contract JuvantiaPaymentsTest is ProtocolFixture {
    bytes32 internal constant LEASING_CATEGORY = keccak256("LEASING");
    bytes32 internal constant CLOUD_MENU_CATEGORY = keccak256("CLOUD_MENU");

    event TaxRateSet(bytes32 indexed categoryId, uint256 newRateBps);
    event TaxReceived(address indexed source, uint256 amount, bytes32 indexed categoryId);
    event TreasurySpent(address indexed recipient, uint256 amount, string purpose);
    event PaymentProcessed(bytes32 indexed paymentId, address indexed payer, address indexed assetToken, bytes32 categoryId, uint256 amount, uint256 tax, uint256 net);

    function testServiceReceiptHasAllBusinessIdentifiers() public {
        bytes32 requestId = keccak256("service-request");
        uint256 amount = 12 ether + 123456789012345678;
        vm.startPrank(alice);
        euroToken.approve(address(services), amount);
        vm.expectEmit(true, true, true, true, address(services));
        emit JuvantiaServicePayments.ServicePaid(requestId, alice, carol, amount);
        services.pay(requestId, carol, amount);
        assertEq(euroToken.balanceOf(carol), amount);
        vm.expectRevert("Already paid");
        services.pay(requestId, carol, amount);
        vm.stopPrank();
    }

    function testAnotherPayerCannotConsumeRequest() public {
        bytes32 requestId = keccak256("shared-request");
        vm.startPrank(bob);
        euroToken.approve(address(services), 1 ether);
        services.pay(requestId, carol, 1 ether);
        vm.stopPrank();
        vm.startPrank(alice);
        euroToken.approve(address(services), 10 ether);
        services.pay(requestId, carol, 10 ether);
        vm.stopPrank();
        assertTrue(services.paid(alice, requestId));
        assertEq(euroToken.balanceOf(carol), 11 ether);
    }

    function testRevertedTransferDoesNotConsumeRequest() public {
        vm.startPrank(alice);
        vm.expectRevert();
        services.pay(bytes32(uint256(1)), carol, 1 ether);
        vm.stopPrank();
        assertFalse(services.paid(alice, bytes32(uint256(1))));
    }

    function testUniversalPaymentAtomicWithTaxAndRevenue() public {
        // Set leasing tax rate in Aerarium to 10% (1,000 bps)
        vm.expectEmit(true, false, false, true, address(aerarium));
        emit TaxRateSet(LEASING_CATEGORY, 1_000);
        aerarium.setTaxRate(LEASING_CATEGORY, 1_000);
        assertEq(aerarium.getTaxRateBps(LEASING_CATEGORY), 1_000);

        bytes32 paymentId = keccak256("lease-slot-1");
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 100 ether);

        vm.expectEmit(true, true, false, true, address(aerarium));
        emit TaxReceived(address(revenue), 10 ether, LEASING_CATEGORY);

        vm.expectEmit(true, true, true, true, address(revenue));
        emit PaymentProcessed(paymentId, bob, address(asset), LEASING_CATEGORY, 100 ether, 10 ether, 90 ether);

        revenue.processPayment(address(asset), 100 ether, LEASING_CATEGORY, paymentId);
        vm.stopPrank();

        assertEq(euroToken.balanceOf(address(aerarium)), 10 ether);
        assertEq(aerarium.totalCollected(), 10 ether);
        assertEq(revenue.claimable(address(asset), alice), 90 ether);
        assertTrue(revenue.paid(bob, paymentId));

        // Replay of the same paymentId is rejected
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 100 ether);
        vm.expectRevert("Already paid");
        revenue.processPayment(address(asset), 100 ether, LEASING_CATEGORY, paymentId);
        vm.stopPrank();
    }

    function testPaymentWithoutTaxWhenRateZero() public {
        // Default tax rate is 0
        assertEq(aerarium.getTaxRateBps(CLOUD_MENU_CATEGORY), 0);

        bytes32 paymentId = keccak256("menu-item-1");
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 50 ether);
        revenue.processPayment(address(asset), 50 ether, CLOUD_MENU_CATEGORY, paymentId);
        vm.stopPrank();

        assertEq(euroToken.balanceOf(address(aerarium)), 0);
        assertEq(aerarium.totalCollected(), 0);
        assertEq(revenue.claimable(address(asset), alice), 50 ether);
        assertTrue(revenue.paid(bob, paymentId));
    }

    function testUnknownAssetDoesNotTakeMoney() public {
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 100 ether);
        vm.expectRevert("Unknown asset");
        revenue.processPayment(address(euroToken), 100 ether, LEASING_CATEGORY, keccak256("invalid-asset-payment"));
        vm.stopPrank();
        assertEq(euroToken.balanceOf(bob), 1_000 ether);
    }

    function testTaxAndTreasuryRequireAdmin() public {
        bytes32 category = keccak256("CLOUD_MENU");

        // Non-owner cannot set tax rate or spend
        vm.startPrank(bob);
        vm.expectRevert();
        aerarium.setTaxRate(category, 500);
        vm.expectRevert();
        aerarium.spend(bob, 1 ether, "unauthorized");
        vm.expectRevert();
        revenue.setAerarium(bob);
        vm.stopPrank();

        // Rate over 10_000 bps (100%) must revert
        vm.expectRevert("Invalid tax rate");
        aerarium.setTaxRate(category, 10_001);

        // Zero bytes32 category must revert
        vm.expectRevert("Invalid category");
        aerarium.setTaxRate(bytes32(0), 500);

        // Empty purpose must revert
        vm.expectRevert("Empty purpose");
        aerarium.spend(bob, 1 ether, "");

        // Zero recipient or zero amount must revert
        vm.expectRevert("Invalid payment");
        aerarium.spend(address(0), 1 ether, "valid purpose");
        vm.expectRevert("Invalid payment");
        aerarium.spend(bob, 0, "valid purpose");
    }

    function testTreasurySpending() public {
        bytes32 category = keccak256("CONSORTIUM_INCORPORATION");
        euroToken.approve(address(aerarium), 20 ether);

        vm.expectEmit(true, true, false, true, address(aerarium));
        emit TaxReceived(address(this), 20 ether, category);
        aerarium.receiveTax(20 ether, category);

        vm.expectEmit(true, false, false, true, address(aerarium));
        emit TreasurySpent(carol, 12 ether, "equipment upgrade");
        aerarium.spend(carol, 12 ether, "equipment upgrade");

        assertEq(aerarium.totalSpent(), 12 ether);
        assertEq(euroToken.balanceOf(carol), 12 ether);
        assertEq(euroToken.balanceOf(address(aerarium)), 8 ether);
    }

    function testReceiveTaxZeroAmountReverts() public {
        vm.expectRevert("Zero amount");
        aerarium.receiveTax(0, LEASING_CATEGORY);
    }

    function testPaymentValidationZeroAmountOrZeroIdReverts() public {
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 10 ether);
        vm.expectRevert("Invalid payment");
        revenue.processPayment(address(asset), 0, LEASING_CATEGORY, keccak256("id-1"));

        vm.expectRevert("Invalid payment");
        revenue.processPayment(address(asset), 10 ether, LEASING_CATEGORY, bytes32(0));
        vm.stopPrank();
    }
}
