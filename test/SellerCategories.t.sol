// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SellerCategoriesTest is ProtocolFixture {
    function testSameCategoryAcceptsDifferentSellerPrices() public {
        _publish("ARBITRARY_SELLER_CATEGORY", true, 3, 0, 1377);
        bytes32 category = keccak256("ARBITRARY_SELLER_CATEGORY");
        uint256 first = revenue.pay(category, keccak256("first"), 101, 0, alice);
        uint256 second = revenue.pay(category, keccak256("second"), 202, 0, bob);
        assertEq(first, 88);
        assertEq(second, 175);
        assertEq(revenue.accountRevenue(alice), 88);
        assertEq(revenue.accountRevenue(bob), 175);
        assertEq(aerarium.totalCollected(), 40);
    }

    function testPoolFundingUsesSuppliedCategoryAndNeverSubstitutesOne() public {
        _publish("SELLER_POOL_CHOICE", true, 2, 0, 2500);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("SELLER_POOL_CHOICE"));
        assertEq(revenue.totalDistributed(address(asset)), 75 ether);
        assertEq(aerarium.totalCollected(), 25 ether);
        vm.expectRevert("Unknown rule");
        revenue.distributeRevenue(address(asset), 100 ether, bytes32(0));
    }

    function testTradeSnapshotsSellerCategoryPriceAndPublishedRevision() public {
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
        _publish("SELLER_ORDER_CHOICE", false, 4, 1, 1200);
        bytes32 category = keccak256("SELLER_ORDER_CHOICE");
        vm.startPrank(alice);
        asset.approve(address(hub), 10 ether);
        uint256 order = hub.createOrder(address(asset), 10 ether, 3 ether, category);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
        _publish("SELLER_ORDER_CHOICE", false, 4, 1, 4500);
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 6 ether);
        hub.fillOrder(order, 2 ether);
        vm.stopPrank();
        assertEq(hub.orderCategory(order), category);
        assertEq(hub.orderRevision(order), 1);
        assertEq(revenue.pendingTradeProceeds(alice), 5.28 ether);
        assertEq(aerarium.totalCollected(), 0.72 ether);
    }

    function testBudgetReviewUsesSellerCategoryAndItsExactRevision() public {
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("fund-budget"), 10 ether, 0, address(aerarium));
        _publish("SELLER_BUDGET_CHOICE", false, 1, 16, 1500);
        bytes32 category = keccak256("SELLER_BUDGET_CHOICE");
        aerarium.spendReviewed(carol, 6 ether, "Seller invoice", category, 1);
        assertEq(revenue.accountRevenue(carol), 5.1 ether);
        _publish("SELLER_BUDGET_CHOICE", false, 1, 16, 1800);
        vm.expectRevert("Rule changed");
        aerarium.spendReviewed(carol, 1 ether, "Seller invoice", category, 1);
    }
}
