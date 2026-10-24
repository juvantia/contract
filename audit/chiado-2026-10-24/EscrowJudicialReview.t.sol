// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "../../test/ProtocolFixture.sol";
import {JuvantiaTradeHub} from "../../src/JuvantiaTradeHub.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Audit reproduction: passing tests confirm known incorrect behavior, not readiness.
contract ReviewSettlementTest is ProtocolFixture {
    function testAuditJudicialTransferFromEscrowDuplicatesRevenueAndStealsOtherCredits() public {
        JuvantiaTradeHub hub = JuvantiaTradeHub(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaTradeHub()),
                    abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue)))
                )
            )
        );
        revenue.setEscrow(address(hub), true);
        revenue.setPaymentSource(address(hub), 1);
        asset.setTribunal(address(this));
        vm.startPrank(alice);
        asset.approve(address(hub), 100_000 ether);
        uint256 order = hub.createOrder(address(asset), 100_000 ether, 1 ether, keccak256("SHARE_TRADE"));
        vm.stopPrank();
        asset.judicialTransfer(address(hub), bob, 100_000 ether);
        assertEq(revenue.effectiveBalanceOf(address(asset), alice), 100_000 ether);
        assertEq(revenue.effectiveBalanceOf(address(asset), bob), 100_000 ether);
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("unrelated"), 100 ether, 0, carol);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        assertEq(revenue.claimFor(address(asset), alice), 100 ether);
        assertEq(revenue.claimFor(address(asset), bob), 100 ether);
        assertEq(revenue.totalClaimed(address(asset)), 200 ether);
        assertEq(revenue.totalDistributed(address(asset)), 100 ether);
        vm.expectRevert();
        revenue.claimAccountFor(carol);
        vm.prank(alice);
        vm.expectRevert();
        hub.cancelOrder(order);
    }
}
