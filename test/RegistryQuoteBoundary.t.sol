// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {PaymentSettlement} from "../src/PaymentSettlement.sol";

contract RegistryQuoteBoundaryTest is ProtocolFixture {
    uint256 private constant ISSUER_KEY = 0x1872;
    bytes32 private constant SERVICE = keccak256("SERVICE_ENTITLEMENT");

    function setUp() public override {
        super.setUp();
        registry.setInvoiceIssuer(vm.addr(ISSUER_KEY), true);
    }

    function testOrderCreatedBeforeSameBlockRuleUpdateRetainsItsRevision() public {
        JuvantiaTradeHub trade = JuvantiaTradeHub(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaTradeHub()),
                    abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue)))
                )
            )
        );
        revenue.setEscrow(address(trade), true);
        revenue.setPaymentSource(address(trade), 1);
        vm.startPrank(alice);
        asset.approve(address(trade), 100 ether);
        uint256 order = trade.createOrder(address(asset), 100 ether, 1 ether, keccak256("SHARE_TRADE"));
        vm.stopPrank();
        _publish("SHARE_TRADE", false, 4, 1, 2000);
        vm.warp(block.timestamp + 1);
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 100 ether);
        trade.fillOrder(order, 100 ether);
        vm.stopPrank();
        assertEq(revenue.tradeProceeds(address(asset), alice), 100 ether);
        assertEq(aerarium.totalCollected(), 0);
        assertEq(asset.balanceOf(bob), 100 ether);
    }

    function testSignedInvoiceCreatedBeforeSameBlockRuleUpdateRetainsItsRevision() public {
        PaymentSettlement.Invoice memory quote = _invoice(keccak256("same-block"), block.timestamp);
        bytes memory signature = _sign(quote);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 2000);
        vm.startPrank(alice);
        euroToken.approve(address(revenue), 100 ether);
        revenue.payInvoice(quote, signature);
        vm.stopPrank();
        assertEq(revenue.accountRevenue(carol), 100 ether);
        assertEq(aerarium.totalCollected(), 0);
    }

    function testOldRevisionCannotBeIssuedAfterSupersedingTimestamp() public {
        vm.warp(block.timestamp + 1);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 2000);
        vm.warp(block.timestamp + 1);
        PaymentSettlement.Invoice memory quote = _invoice(keccak256("late-old"), block.timestamp);
        bytes memory signature = _sign(quote);
        vm.startPrank(alice);
        euroToken.approve(address(revenue), 100 ether);
        vm.expectRevert("Stale quote");
        revenue.payInvoice(quote, signature);
        vm.stopPrank();
        assertFalse(revenue.paid(alice, quote.payment.paymentId));
    }

    function testSameBlockBoundaryDoesNotExtendExpiryOrBypassIssuerAuthorization() public {
        PaymentSettlement.Invoice memory quote = _invoice(keccak256("expiry"), block.timestamp);
        bytes memory signature = _sign(quote);
        bytes memory unauthorizedSignature = _signWithKey(quote, 0xBAD);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 2000);
        vm.startPrank(alice);
        euroToken.approve(address(revenue), 100 ether);
        vm.expectRevert("Invalid invoice signature");
        revenue.payInvoice(quote, unauthorizedSignature);
        vm.stopPrank();
        vm.warp(quote.payment.expiresAt + 1);
        vm.prank(alice);
        vm.expectRevert("Quote expired");
        revenue.payInvoice(quote, signature);
        assertFalse(revenue.paid(alice, quote.payment.paymentId));
    }

    function _invoice(bytes32 id, uint256 issuedAt) private view returns (PaymentSettlement.Invoice memory) {
        return PaymentSettlement.Invoice(
            PaymentSettlement.Payment(id, SERVICE, 1, 0, carol, address(0), 100 ether, issuedAt, issuedAt + 1 hours),
            alice
        );
    }

    function _sign(PaymentSettlement.Invoice memory quote) private view returns (bytes memory) {
        return _signWithKey(quote, ISSUER_KEY);
    }

    function _signWithKey(PaymentSettlement.Invoice memory quote, uint256 key) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, revenue.hashInvoice(quote));
        return abi.encodePacked(r, s, v);
    }
}
