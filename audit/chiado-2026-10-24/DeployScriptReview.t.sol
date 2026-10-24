// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TestEuroToken} from "../../test/ProtocolFixture.sol";
import {DeployJuvantia} from "../../script/DeployJuvantia.s.sol";
import {JuvantiaPaymentRegistry} from "../../src/JuvantiaPaymentRegistry.sol";
import {ConsortiumFactory} from "../../src/community/ConsortiumFactory.sol";

/// @dev Audit reproduction: passing tests confirm known incorrect behavior, not readiness.
contract DeployScriptAuditTest is Test {
    function testAuditScriptAcceptsDifferentCoreSignersAndDisabledTribunal() public {
        TestEuroToken token = new TestEuroToken();
        vm.setEnv("BLOCKCHAIN_CHAIN_ID", vm.toString(block.chainid));
        vm.setEnv("EURO_TOKEN_ADDRESS", vm.toString(address(token)));
        vm.setEnv("PAYMENT_INVOICE_ISSUER_ADDRESS", vm.toString(address(0x1111)));
        vm.setEnv("COMMUNITY_AUTHORIZER_ADDRESS", vm.toString(address(0x2222)));
        vm.setEnv("TRIBUNAL_ADDRESS", vm.toString(address(0)));
        DeployJuvantia script = new DeployJuvantia();
        vm.recordLogs();
        script.run();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 issuerGrants;
        uint256 factoryAuthorizers;
        uint256 disabledTribunals;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("InvoiceIssuerSet(address,bool)")) {
                JuvantiaPaymentRegistry registry = JuvantiaPaymentRegistry(logs[i].emitter);
                assertTrue(registry.invoiceIssuers(address(0x1111)));
                assertFalse(registry.invoiceIssuers(address(0x2222)));
                ++issuerGrants;
            }
            if (logs[i].topics[0] == keccak256("AuthorizerSet(address)")) {
                assertEq(ConsortiumFactory(logs[i].emitter).authorizer(), address(0x2222));
                ++factoryAuthorizers;
            }
            if (logs[i].topics[0] == keccak256("TribunalSet(address,address)")) {
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(0));
                ++disabledTribunals;
            }
        }
        assertEq(issuerGrants, 1);
        assertEq(factoryAuthorizers, 2);
        assertEq(disabledTribunals, 4);
    }
}
