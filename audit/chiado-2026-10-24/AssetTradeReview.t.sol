// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {JuvantiaTradeHubTest} from "../../test/JuvantiaTradeHub.t.sol";

/// @dev Audit reproduction: passing tests confirm known incorrect behavior, not readiness.
contract AssetTradeReviewTest is JuvantiaTradeHubTest {
    function testAuditQuoteCreatedBeforeSameBlockRulePublicationBecomesUnfillable() public {
        uint256 id = createOrder(100 ether, 1 ether, keccak256("SHARE_TRADE"));
        // A second transaction in the same block changes the rule after this order.
        _publish("SHARE_TRADE", false, 4, 1, 100);
        vm.warp(block.timestamp + 1);
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 100 ether);
        vm.expectRevert("Stale quote");
        trade.fillOrder(id, 100 ether);
        vm.stopPrank();
        vm.prank(alice);
        trade.cancelOrder(id);
        assertEq(asset.balanceOf(alice), 100_000 ether);
    }

    function testAuditDirectSellerSeizureCannotReachListedShares() public {
        createOrder(100_000 ether, 1 ether, keccak256("SHARE_TRADE"));
        asset.setTribunal(address(this));
        assertEq(revenue.effectiveBalanceOf(address(asset), alice), 100_000 ether);
        assertEq(asset.balanceOf(alice), 0);
        vm.expectRevert();
        asset.judicialTransfer(alice, bob, 1 ether);
    }
}
