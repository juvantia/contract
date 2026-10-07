// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {PaymentSettlement} from "../src/PaymentSettlement.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";

contract JuvantiaPaymentsTest is ProtocolFixture {
    uint256 private constant ISSUER_KEY = 0x1872;
    bytes32 private constant SERVICE = keccak256("SERVICE_ENTITLEMENT");

    function setUp() public override {
        super.setUp();
        registry.setInvoiceIssuer(vm.addr(ISSUER_KEY), true);
    }

    function invoice(bytes32 id, uint256 gross) private view returns (PaymentSettlement.Invoice memory) {
        return PaymentSettlement.Invoice(
            PaymentSettlement.Payment(
                id,
                SERVICE,
                registry.currentRevision(SERVICE),
                0,
                carol,
                address(0),
                gross,
                block.timestamp,
                block.timestamp + 1 hours
            ),
            alice,
            address(services)
        );
    }

    function sign(PaymentSettlement.Invoice memory quote) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_KEY, revenue.hashInvoice(quote));
        return abi.encodePacked(r, s, v);
    }

    function testServiceAccruesOnlyInDistributorAndClaimIsUntaxed() public {
        PaymentSettlement.Invoice memory quote = invoice(keccak256("invoice"), 12 ether + 123);
        bytes memory signature = sign(quote);
        vm.startPrank(alice);
        euroToken.approve(address(revenue), quote.payment.gross);
        services.pay(quote, signature);
        vm.expectRevert("Already paid");
        services.pay(quote, signature);
        vm.stopPrank();
        assertEq(euroToken.balanceOf(carol), 0);
        assertEq(euroToken.balanceOf(address(services)), 0);
        assertEq(revenue.accountRevenue(carol), quote.payment.gross);
        assertEq(revenue.claimAccountFor(carol), quote.payment.gross);
        assertEq(euroToken.balanceOf(carol), quote.payment.gross);
    }

    function testOldIssuedInvoiceSurvivesRuleUpdateButBarePaymentsUseCurrent() public {
        PaymentSettlement.Invoice memory quote = invoice(keccak256("quote"), 100 ether);
        bytes memory signature = sign(quote);
        vm.warp(block.timestamp + 1);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 2000);
        vm.startPrank(alice);
        euroToken.approve(address(revenue), 100 ether);
        services.pay(quote, signature);
        vm.stopPrank();
        assertEq(revenue.accountRevenue(carol), 100 ether);
        _publish("OPERATING_RECEIPT", true, 1, 0, 2000);
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("current"), 100 ether, 0, bob);
        assertEq(revenue.accountRevenue(bob), 80 ether);
        assertEq(aerarium.totalCollected(), 20 ether);
    }

    function testTamperedWrongPayerExpiredAndUnsignedInvoicesFailWithoutConsumption() public {
        PaymentSettlement.Invoice memory quote = invoice(keccak256("quote"), 10 ether);
        bytes memory signature = sign(quote);
        vm.prank(bob);
        vm.expectRevert("Invoice payer mismatch");
        services.pay(quote, signature);
        quote.payment.gross += 1;
        vm.prank(alice);
        vm.expectRevert("Invalid invoice signature");
        services.pay(quote, signature);
        quote.payment.gross -= 1;
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        vm.expectRevert("Quote expired");
        services.pay(quote, signature);
        assertFalse(revenue.paid(alice, quote.payment.paymentId));
        assertFalse(services.paid(alice, quote.payment.paymentId));
    }

    function testPublicMerchantCanFundOwnBalanceButCannotPullFromOthersOrUseInternalType() public {
        vm.startPrank(alice);
        euroToken.approve(address(revenue), 10 ether);
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("merchant"), 10 ether, 0, bob);
        vm.expectRevert("Not payment source");
        revenue.payFor(PaymentSettlement.Payment(keccak256("steal"), SERVICE, 0, 0, bob, address(0), 1, 0, 0), bob);
        vm.expectRevert("Restricted category");
        revenue.pay(keccak256("CONSORTIUM_DISTRIBUTION"), keccak256("internal"), 1, 1, address(asset));
        vm.stopPrank();
        assertEq(revenue.accountRevenue(bob), 10 ether);
    }

    function testUnknownInactiveAndInvalidTaxRevertAtomically() public {
        vm.expectRevert("Unknown rule");
        revenue.pay(bytes32(uint256(1)), bytes32(uint256(2)), 1, 0, alice);
        JuvantiaPaymentRegistry.Rule memory rule = JuvantiaPaymentRegistry.Rule(false, true, 1, 0, 0);
        registry.publish(keccak256("OFF"), rule);
        vm.expectRevert("Inactive rule");
        revenue.pay(keccak256("OFF"), bytes32(uint256(2)), 1, 0, alice);
        rule.active = true;
        rule.taxBps = 10001;
        vm.expectRevert("Invalid rates");
        registry.publish(keccak256("INVALID_TAX"), rule);
        assertEq(registry.currentRevision(keccak256("INVALID_TAX")), 0);
        assertFalse(revenue.paid(address(this), bytes32(uint256(2))));
    }

    function testFuzzConservationAndRounding(uint96 raw, uint16 tax_) public {
        uint256 gross = bound(raw, 1, 100_000 ether);
        uint16 tax = uint16(bound(tax_, 0, 10000));
        registry.publish(keccak256("COMMERCIAL"), JuvantiaPaymentRegistry.Rule(true, true, 1, tax, 0));
        uint256 beforeBalance = euroToken.balanceOf(address(this));
        revenue.pay(keccak256("COMMERCIAL"), keccak256("conservation"), gross, 0, alice);
        assertEq(beforeBalance - euroToken.balanceOf(address(this)), gross);
        uint256 expectedTax = gross * tax / 10000;
        assertEq(revenue.accountRevenue(alice), gross - expectedTax);
        assertEq(aerarium.totalCollected(), expectedTax);
        assertEq(revenue.accountRevenue(carol), 0);
        assertEq(revenue.accountRevenue(alice) + aerarium.totalCollected(), gross);
        assertEq(euroToken.balanceOf(address(revenue)) + euroToken.balanceOf(address(aerarium)), gross);
    }

    function testAddressedClaimAllAndJudicialEncumbrance() public {
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("address"), 10 ether, 0, alice);
        revenue.distributeRevenue(address(asset), 20 ether, keccak256("ASSET_REVENUE"));
        revenue.setTribunal(address(this));
        revenue.setEncumbrance(alice, true);
        address[] memory assets = new address[](1);
        assets[0] = address(asset);
        vm.prank(alice);
        vm.expectRevert("Account encumbered");
        revenue.claimAll(assets);
        revenue.judicialClaimAccount(alice, bob, 3 ether);
        revenue.setEncumbrance(alice, false);
        vm.prank(alice);
        assertEq(revenue.claimAll(assets), 27 ether);
        assertEq(revenue.claimAccountFor(bob), 3 ether);
    }

    function testFullyChargedPoolPaymentConservesGrossWithoutCreatingEarnings() public {
        _publish("LEASING", true, 2, 0, 10000);
        revenue.processPayment(address(asset), 10 ether, keccak256("LEASING"), keccak256("full-charge"));
        assertEq(aerarium.totalCollected(), 10 ether);
        assertEq(revenue.totalDistributed(address(asset)), 0);
        assertEq(revenue.claimable(address(asset), alice), 0);
    }

    function testBudgetCanSpendAddressedReceiptsThroughDistributor() public {
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("civic-receipt"), 10 ether, 0, address(aerarium));
        assertEq(euroToken.balanceOf(address(aerarium)), 0);
        assertEq(revenue.accountRevenue(address(aerarium)), 10 ether);
        aerarium.spendReviewed(carol, 6 ether, "equipment", keccak256("BUDGET_EXPENSE"), 1);
        assertEq(revenue.accountRevenue(address(aerarium)), 0);
        assertEq(revenue.accountRevenue(carol), 6 ether);
        assertEq(euroToken.balanceOf(address(aerarium)), 4 ether);
        assertEq(euroToken.balanceOf(carol), 0);
        assertEq(aerarium.totalSpent(), 6 ether);
    }

    function testBudgetSpendingAndCatalogUseRegistry() public {
        _publish("LEASING", true, 2, 0, 1000);
        revenue.processPayment(address(asset), 100 ether, keccak256("LEASING"), keccak256("lease"));
        assertEq(aerarium.getTaxRateBps(keccak256("LEASING")), 1000);
        _publish("BUDGET_EXPENSE", false, 1, 16, 1000);
        vm.expectRevert("Rule changed");
        aerarium.spendReviewed(carol, 6 ether, "equipment", keccak256("BUDGET_EXPENSE"), 1);
        aerarium.spendReviewed(carol, 6 ether, "equipment", keccak256("BUDGET_EXPENSE"), 2);
        assertEq(euroToken.balanceOf(carol), 0);
        assertEq(revenue.accountRevenue(carol), 5.4 ether);
        assertEq(aerarium.totalSpent(), 6 ether);
        assertEq(euroToken.balanceOf(address(aerarium)), 4.6 ether);
        assertEq(aerarium.totalCollected(), 10.6 ether);
        JuvantiaPaymentRegistry.Rule memory rule = registry.currentRule(keccak256("LEASING"));
        vm.prank(bob);
        vm.expectRevert();
        registry.publish(keccak256("LEASING"), rule);
        vm.prank(bob);
        vm.expectRevert("Only distributor");
        aerarium.receiveTax(1, keccak256("LEASING"));
    }
}
