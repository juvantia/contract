// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract JuvantiaTradeHubTest is ProtocolFixture {
    JuvantiaTradeHub internal trade;

    function setUp() public override {
        super.setUp();
        trade = JuvantiaTradeHub(address(new ERC1967Proxy(address(new JuvantiaTradeHub()),
            abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue))))));
        revenue.setEscrow(address(trade), true);
    }

    function createOrder(uint256 amount, uint256 price) internal returns (uint256 id) {
        vm.startPrank(alice);
        asset.approve(address(trade), amount);
        id = trade.createOrder(address(asset), amount, price);
        vm.stopPrank();
    }

    function testFillAndWithdrawExactEuro() public {
        uint256 id = createOrder(100 ether, 5 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 200 ether);
        trade.fillOrder(id, 40 ether);
        vm.stopPrank();
        (,, uint256 remaining,, bool active) = trade.orders(id);
        assertEq(remaining, 60 ether);
        assertTrue(active);
        assertEq(asset.balanceOf(bob), 40 ether);
        assertEq(trade.pendingWithdrawals(alice), 200 ether);
        vm.prank(alice);
        trade.withdraw();
        assertEq(euroToken.balanceOf(alice), 1_200 ether);
        assertEq(trade.pendingWithdrawals(alice), 0);
    }

    function testSellerEarnsRevenueWhileSharesAreListed() public {
        uint256 id = createOrder(100_000 ether, 1);
        revenue.distributeRevenue(address(asset), 100 ether);
        assertEq(revenue.claimable(address(asset), alice), 100 ether);
        assertEq(revenue.claimable(address(asset), address(trade)), 0);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 100_000);
        trade.fillOrder(id, 100_000 ether);
        vm.stopPrank();
        assertEq(revenue.claimFor(address(asset), bob), 0);
        assertEq(revenue.claimFor(address(asset), alice), 100 ether);
        revenue.distributeRevenue(address(asset), 200 ether);
        assertEq(revenue.claimFor(address(asset), bob), 200 ether);
        assertEq(revenue.claimFor(address(asset), alice), 0);
    }

    function testCancellationRestoresSharesWithoutDoubleRevenue() public {
        revenue.distributeRevenue(address(asset), 10 ether);
        uint256 id = createOrder(100_000 ether, 1);
        revenue.distributeRevenue(address(asset), 20 ether);
        vm.prank(alice);
        trade.cancelOrder(id);
        assertEq(asset.balanceOf(alice), 100_000 ether);
        assertEq(revenue.escrowedFor(address(asset), alice), 0);
        assertEq(revenue.claimFor(address(asset), alice), 30 ether);
        assertEq(revenue.claimFor(address(asset), alice), 0);
    }

    function testEscrowRevocationDoesNotStrandSellers() public {
        uint256 id = createOrder(100 ether, 1 ether);
        revenue.setEscrow(address(trade), false);
        vm.prank(alice);
        trade.cancelOrder(id);
        assertEq(asset.balanceOf(alice), 100_000 ether);
    }

    function testAnotherUserCannotCancelOrWithdraw() public {
        uint256 id = createOrder(100 ether, 1 ether);
        vm.startPrank(bob);
        vm.expectRevert("Not the seller");
        trade.cancelOrder(id);
        vm.expectRevert("No funds to withdraw");
        trade.withdraw();
        vm.stopPrank();
    }

    function testTinyFillRoundsUpAndNeverTransfersForFree() public {
        uint256 id = createOrder(1 ether, 1);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 1);
        trade.fillOrder(id, 1);
        vm.stopPrank();
        assertEq(trade.pendingWithdrawals(alice), 1);
        assertEq(asset.balanceOf(bob), 1);
    }

    function testForgedEscrowPositionRejected() public {
        vm.expectRevert("Invalid escrow asset");
        revenue.escrowDeposit(address(asset), bob, 1 ether);
        vm.expectRevert("Invalid position");
        revenue.escrowWithdraw(address(asset), alice, 1 ether);
    }
}
