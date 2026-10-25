// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProtocolFixture} from "./ProtocolFixture.sol";
import {PaymentSettlement} from "../src/PaymentSettlement.sol";

contract InvoiceWallet {
    function approve(IERC20 token, address distributor, uint256 gross) external {
        token.approve(distributor, gross);
    }

    function pay(PaymentSettlement distributor, PaymentSettlement.Invoice calldata invoice, bytes calldata signature)
        external
    {
        distributor.payInvoice(invoice, signature);
    }
}

contract DirectInvoicesTest is ProtocolFixture {
    uint256 private constant ISSUER_KEY = 0x1872;
    bytes32 private constant CATEGORY = keccak256("SERVICE_ENTITLEMENT");

    function setUp() public override {
        super.setUp();
        registry.setInvoiceIssuer(vm.addr(ISSUER_KEY), true);
    }

    function quote(address payer, bytes32 category) private view returns (PaymentSettlement.Invoice memory) {
        return PaymentSettlement.Invoice(
            PaymentSettlement.Payment(
                keccak256("direct-invoice"),
                category,
                registry.currentRevision(category),
                0,
                carol,
                address(0),
                101,
                block.timestamp,
                block.timestamp + 1 hours
            ),
            payer
        );
    }

    function sign(PaymentSettlement.Invoice memory invoice) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_KEY, revenue.hashInvoice(invoice));
        return abi.encodePacked(r, s, v);
    }

    function testSmartWalletPaysPrivateInvoiceDirectlyWithExactSettlement() public {
        _publish("SERVICE_ENTITLEMENT", false, 1, 2, 3333);
        InvoiceWallet wallet = new InvoiceWallet();
        euroToken.mint(address(wallet), 101);
        PaymentSettlement.Invoice memory invoice = quote(address(wallet), CATEGORY);
        wallet.approve(euroToken, address(revenue), 101);
        vm.recordLogs();
        wallet.pay(revenue, invoice, sign(invoice));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 settlements;
        for (uint256 i; i < logs.length; i++) {
            if (
                logs[i].topics[0]
                    != keccak256(
                        "Settlement(bytes32,address,address,address,bytes32,uint256,uint8,address,uint256,uint256,uint256)"
                    )
            ) continue;
            settlements++;
            assertEq(logs[i].emitter, address(revenue));
            assertEq(logs[i].topics[1], invoice.payment.paymentId);
            assertEq(logs[i].topics[2], bytes32(uint256(uint160(address(wallet)))));
            assertEq(logs[i].topics[3], bytes32(uint256(uint160(carol))));
            assertEq(
                logs[i].data,
                abi.encode(
                    address(wallet), CATEGORY, uint256(2), uint8(0), address(0), uint256(101), uint256(33), uint256(68)
                )
            );
        }
        assertEq(settlements, 1);
        assertEq(revenue.sourceRoles(address(wallet)), 0);
        assertEq(euroToken.allowance(address(wallet), address(revenue)), 0);
        assertEq(euroToken.balanceOf(address(wallet)), 0);
        assertEq(revenue.accountRevenue(carol), 68);
        assertEq(aerarium.totalCollected(), 33);
    }

    function testInvoiceRoleCannotBeGrantedOrUsedByUnsignedModule() public {
        InvoiceWallet module = new InvoiceWallet();
        vm.expectRevert("Invalid source");
        revenue.setPaymentSource(address(module), 2);
        vm.expectRevert("Invalid source");
        revenue.setPaymentSource(address(module), 31);
        revenue.setPaymentSource(address(module), 1);
        PaymentSettlement.Invoice memory invoice = quote(alice, CATEGORY);
        vm.prank(address(module));
        vm.expectRevert("Restricted category");
        revenue.payFor(invoice.payment, alice);
        vm.prank(alice);
        vm.expectRevert("Restricted category");
        revenue.pay(CATEGORY, invoice.payment.paymentId, 101, 0, carol);
        assertEq(revenue.sourceRoles(address(module)), 1);
        assertFalse(revenue.paid(alice, invoice.payment.paymentId));
    }

    function testInvoiceDoesNotGrantOtherModuleRoles() public {
        for (uint256 role = 4; role <= 16; role *= 2) {
            _publish("MODULE_ONLY", false, 1, role, 0);
            PaymentSettlement.Invoice memory invoice = quote(alice, keccak256("MODULE_ONLY"));
            bytes memory signature = sign(invoice);
            vm.prank(alice);
            vm.expectRevert("Restricted category");
            revenue.payInvoice(invoice, signature);
            assertFalse(revenue.paid(alice, invoice.payment.paymentId));
        }
    }

    function testRevokedIssuerAndMissingSignatureCannotConsumeInvoice() public {
        PaymentSettlement.Invoice memory invoice = quote(alice, CATEGORY);
        bytes memory signature = sign(invoice);
        registry.setInvoiceIssuer(vm.addr(ISSUER_KEY), false);
        vm.startPrank(alice);
        vm.expectRevert("Invalid invoice signature");
        revenue.payInvoice(invoice, signature);
        vm.expectRevert();
        revenue.payInvoice(invoice, "");
        vm.stopPrank();
        assertFalse(revenue.paid(alice, invoice.payment.paymentId));
        assertEq(revenue.accountRevenue(carol), 0);
    }

    function testFundingFailureCanRetryAndPublicPathSharesReplayProtection() public {
        PaymentSettlement.Invoice memory invoice = quote(alice, keccak256("OPERATING_RECEIPT"));
        bytes memory signature = sign(invoice);
        vm.startPrank(alice);
        vm.expectRevert();
        revenue.payInvoice(invoice, signature);
        assertFalse(revenue.paid(alice, invoice.payment.paymentId));
        euroToken.approve(address(revenue), 202);
        revenue.payInvoice(invoice, signature);
        vm.expectRevert("Already paid");
        revenue.pay(invoice.payment.categoryId, invoice.payment.paymentId, 101, 0, carol);
        invoice.payment.paymentId = keccak256("public-first");
        revenue.pay(invoice.payment.categoryId, invoice.payment.paymentId, 101, 0, carol);
        vm.stopPrank();
        signature = sign(invoice);
        vm.prank(alice);
        vm.expectRevert("Already paid");
        revenue.payInvoice(invoice, signature);
        assertEq(revenue.accountRevenue(carol), 202);
    }
}
