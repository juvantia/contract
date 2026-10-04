// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract JuvantiaTradeHubTest is ProtocolFixture {
    JuvantiaTradeHub internal trade;

    function setUp() public override {
        super.setUp();
        trade = JuvantiaTradeHub(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaTradeHub()),
                    abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue)))
                )
            )
        );
        revenue.setEscrow(address(trade), true);
    }

    function createOrder(uint256 amount, uint256 price) internal returns (uint256 id) {
        vm.startPrank(alice);
        asset.approve(address(trade), amount);
        id = trade.createOrder(address(asset), amount, price);
        vm.stopPrank();
    }

    function testFillAndClaimExactEuroThroughDistributor() public {
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
        assertEq(revenue.tradeProceeds(address(asset), alice), 200 ether);
        assertEq(revenue.claimable(address(asset), alice), 200 ether);
        assertEq(euroToken.balanceOf(address(trade)), 0);
        assertEq(euroToken.balanceOf(address(revenue)), 200 ether);
        assertEq(euroToken.allowance(address(trade), address(revenue)), 0);
        assertEq(revenue.cumulativeIndex(address(asset)), 0);
        assertEq(revenue.totalDistributed(address(asset)), 0);
        assertEq(revenue.totalTradeDeposited(address(asset)), 200 ether);
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(revenue));
        emit JuvantiaRevenueDistributor.RevenueClaimed(address(asset), alice, 200 ether);
        assertEq(revenue.claim(address(asset)), 200 ether);
        assertEq(euroToken.balanceOf(alice), 1_200 ether);
        assertEq(trade.pendingWithdrawals(alice), 0);
        assertEq(revenue.totalClaimed(address(asset)), 0);
        assertEq(revenue.totalTradeClaimed(address(asset)), 200 ether);
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
        assertEq(revenue.claimFor(address(asset), alice), 100 ether + 100_000);
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

    function testAnotherUserCannotCancelOrReceiveSellerProceeds() public {
        uint256 id = createOrder(100 ether, 1 ether);
        vm.startPrank(bob);
        vm.expectRevert("Not the seller");
        trade.cancelOrder(id);
        assertEq(revenue.claim(address(asset)), 0);
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

    function testTradeHubHasNoWithdrawalEntryPoint() public {
        uint256 id = createOrder(100 ether, 1 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 100 ether);
        trade.fillOrder(id, 100 ether);
        vm.stopPrank();
        vm.prank(alice);
        (bool success,) = address(trade).call(abi.encodeWithSignature("withdraw()"));
        assertFalse(success);
        assertEq(euroToken.balanceOf(alice), 1_000 ether);
        assertEq(revenue.claimable(address(asset), alice), 100 ether);
    }

    function testClaimForAlwaysPaysSellerAfterAllSharesAreSold() public {
        uint256 id = createOrder(100_000 ether, 1);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 100_000);
        trade.fillOrder(id, 100_000 ether);
        vm.stopPrank();
        assertEq(revenue.effectiveBalanceOf(address(asset), alice), 0);
        vm.prank(carol);
        assertEq(revenue.claimFor(address(asset), alice), 100_000);
        assertEq(euroToken.balanceOf(alice), 1_000 ether + 100_000);
        assertEq(euroToken.balanceOf(carol), 0);
        assertEq(revenue.claimFor(address(asset), alice), 0);
        assertEq(trade.pendingWithdrawals(alice), 0);
    }

    function testMultipleSellersAndFillsKeepProceedsSeparate() public {
        vm.prank(alice);
        asset.transfer(carol, 100 ether);
        uint256 id = createOrder(100 ether, 2 ether);
        vm.startPrank(carol);
        asset.approve(address(trade), 100 ether);
        uint256 otherId = trade.createOrder(address(asset), 100 ether, 1 ether);
        vm.stopPrank();
        vm.startPrank(bob);
        euroToken.approve(address(trade), 300 ether);
        trade.fillOrder(id, 40 ether);
        trade.fillOrder(otherId, 100 ether);
        trade.fillOrder(id, 60 ether);
        vm.stopPrank();
        assertEq(revenue.claimFor(address(asset), alice), 200 ether);
        assertEq(revenue.claimFor(address(asset), carol), 100 ether);
        assertEq(revenue.claimFor(address(asset), bob), 0);
        assertEq(revenue.totalTradeClaimed(address(asset)), 300 ether);
        assertEq(euroToken.balanceOf(address(revenue)), 0);
    }

    function testMixedRevenueBatchAcrossAssetsPaysEachCreditOnlyOnce() public {
        JuvantiaAsset other = JuvantiaAsset(fabrica.createAsset(keccak256("asset-2"), "Apparatus", alice));
        vm.startPrank(alice);
        other.approve(address(trade), 100_000 ether);
        uint256 otherId = trade.createOrder(address(other), 100_000 ether, 1);
        vm.stopPrank();
        uint256 id = createOrder(100_000 ether, 1);
        revenue.distributeRevenue(address(asset), 10 ether);
        revenue.distributeRevenue(address(other), 20 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 200_000);
        trade.fillOrder(id, 100_000 ether);
        trade.fillOrder(otherId, 100_000 ether);
        vm.stopPrank();
        assertEq(trade.pendingWithdrawals(alice), 200_000);
        address[] memory assets = new address[](3);
        assets[0] = address(asset);
        assets[1] = address(other);
        assets[2] = address(asset);
        vm.prank(alice);
        assertEq(revenue.claimBatch(assets), 30 ether + 200_000);
        assertEq(trade.pendingWithdrawals(alice), 0);
        assertEq(revenue.totalClaimed(address(asset)), 10 ether);
        assertEq(revenue.totalClaimed(address(other)), 20 ether);
        assertEq(revenue.totalTradeClaimed(address(other)), 100_000);
        assertEq(euroToken.balanceOf(address(revenue)), 0);
    }

    function testUnfundedOrUnauthorizedTradeCreditsRejected() public {
        vm.expectRevert("Invalid escrow asset");
        revenue.depositTradeProceeds(address(asset), alice, 1 ether);
        vm.prank(address(trade));
        vm.expectRevert("Invalid escrow asset");
        revenue.depositTradeProceeds(address(euroToken), alice, 1 ether);
        vm.prank(address(trade));
        vm.expectRevert("Invalid seller");
        revenue.depositTradeProceeds(address(asset), address(0), 1 ether);
        vm.prank(address(trade));
        vm.expectRevert("Zero amount");
        revenue.depositTradeProceeds(address(asset), alice, 0);
        vm.prank(address(trade));
        vm.expectRevert();
        revenue.depositTradeProceeds(address(asset), alice, 1 ether);
        assertEq(revenue.pendingTradeProceeds(alice), 0);
    }

    function testSettlementFailureRollsBackMoneySharesAndOrder() public {
        uint256 id = createOrder(100 ether, 2 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 200 ether);
        vm.mockCall(
            address(euroToken),
            abi.encodeCall(IERC20.transferFrom, (address(trade), address(revenue), 200 ether)),
            abi.encode(true)
        );
        vm.expectRevert("Incorrect deposit");
        trade.fillOrder(id, 100 ether);
        vm.stopPrank();
        assertFailedFillUnchanged(id);
        vm.clearMockedCalls();

        vm.mockCall(
            address(euroToken), abi.encodeCall(IERC20.transferFrom, (bob, address(trade), 200 ether)), abi.encode(true)
        );
        vm.prank(bob);
        vm.expectRevert("Incorrect payment");
        trade.fillOrder(id, 100 ether);
        assertFailedFillUnchanged(id);
        vm.clearMockedCalls();

        vm.mockCall(address(asset), abi.encodeCall(IERC20.transfer, (bob, 100 ether)), abi.encode(false));
        vm.prank(bob);
        vm.expectRevert();
        trade.fillOrder(id, 100 ether);
        assertFailedFillUnchanged(id);
    }

    function assertFailedFillUnchanged(uint256 id) internal view {
        (,, uint256 remaining,, bool active) = trade.orders(id);
        assertEq(remaining, 100 ether);
        assertTrue(active);
        assertEq(euroToken.balanceOf(bob), 1_000 ether);
        assertEq(euroToken.balanceOf(address(trade)), 0);
        assertEq(euroToken.balanceOf(address(revenue)), 0);
        assertEq(revenue.pendingTradeProceeds(alice), 0);
        assertEq(revenue.totalTradeDeposited(address(asset)), 0);
        assertEq(revenue.escrowedFor(address(asset), alice), 100 ether);
        assertEq(asset.balanceOf(bob), 0);
    }

    function testRevocationBlocksNewCreditsButAllowsClaimsAndCancellation() public {
        uint256 id = createOrder(100 ether, 2 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 200 ether);
        trade.fillOrder(id, 40 ether);
        vm.stopPrank();
        revenue.setEscrow(address(trade), false);
        vm.prank(bob);
        vm.expectRevert("Invalid escrow asset");
        trade.fillOrder(id, 60 ether);
        assertEq(revenue.claimFor(address(asset), alice), 80 ether);
        vm.prank(alice);
        trade.cancelOrder(id);
        assertEq(asset.balanceOf(alice), 99_960 ether);
    }

    function testEncumbranceAndJudicialClaimsCoverYieldAndTradeProceeds() public {
        uint256 id = createOrder(100 ether, 2 ether);
        revenue.distributeRevenue(address(asset), 10 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 200 ether);
        trade.fillOrder(id, 100 ether);
        vm.stopPrank();
        revenue.setTribunal(address(this));
        revenue.setEncumbrance(alice, true);
        vm.prank(alice);
        vm.expectRevert("Account encumbered");
        revenue.claim(address(asset));
        vm.expectRevert("Account encumbered");
        revenue.claimFor(address(asset), alice);
        address[] memory assets = new address[](1);
        assets[0] = address(asset);
        vm.prank(alice);
        vm.expectRevert("Account encumbered");
        revenue.claimBatch(assets);

        vm.prank(bob);
        vm.expectRevert("Only tribunal");
        revenue.judicialClaim(address(asset), alice, carol, 1 ether);
        vm.expectRevert("Insufficient accrued revenue");
        revenue.judicialClaim(address(asset), alice, carol, 211 ether);
        assertEq(revenue.judicialClaim(address(asset), alice, carol, 30 ether), 30 ether);
        assertEq(revenue.totalClaimed(address(asset)), 10 ether);
        assertEq(revenue.totalTradeClaimed(address(asset)), 20 ether);
        assertEq(trade.pendingWithdrawals(alice), 180 ether);
        assertEq(revenue.judicialSeize(address(asset), alice, carol, 20 ether), 20 ether);
        assertEq(revenue.judicialClaimBatch(assets, alice, carol), 160 ether);
        assertEq(euroToken.balanceOf(carol), 210 ether);
        assertEq(revenue.pendingTradeProceeds(alice), 0);
        assertEq(revenue.totalTradeClaimed(address(asset)), 200 ether);

        vm.prank(bob);
        asset.approve(address(trade), 100 ether);
        vm.prank(bob);
        uint256 reverseId = trade.createOrder(address(asset), 100 ether, 1 ether);
        vm.startPrank(alice);
        euroToken.approve(address(trade), 100 ether);
        trade.fillOrder(reverseId, 100 ether);
        vm.stopPrank();
        assertEq(revenue.judicialClaim(address(asset), bob, carol), 100 ether);
        assertEq(revenue.pendingTradeProceeds(bob), 0);
    }

    function testPayoutFailurePreservesTradeCredit() public {
        uint256 id = createOrder(100 ether, 2 ether);
        vm.startPrank(bob);
        euroToken.approve(address(trade), 200 ether);
        trade.fillOrder(id, 100 ether);
        vm.stopPrank();
        vm.mockCall(address(euroToken), abi.encodeCall(IERC20.transfer, (alice, 200 ether)), abi.encode(false));
        vm.expectRevert();
        revenue.claimFor(address(asset), alice);
        assertEq(revenue.claimable(address(asset), alice), 200 ether);
        assertEq(revenue.pendingTradeProceeds(alice), 200 ether);
        assertEq(revenue.totalTradeClaimed(address(asset)), 0);
        vm.clearMockedCalls();
        assertEq(revenue.claimFor(address(asset), alice), 200 ether);
    }

    function testFuzzTradeAndYieldConservation(uint96 listed, uint96 bought, uint96 income) public {
        uint256 amount = bound(uint256(listed), 1, 100_000 ether);
        uint256 filled = bound(uint256(bought), 1, amount);
        uint256 yield = bound(uint256(income), 1, 100_000 ether);
        uint256 id = createOrder(amount, 1);
        uint256 cost = (filled + 1 ether - 1) / 1 ether;
        revenue.distributeRevenue(address(asset), yield);
        vm.startPrank(bob);
        euroToken.approve(address(trade), cost);
        trade.fillOrder(id, filled);
        vm.stopPrank();
        revenue.distributeRevenue(address(asset), yield);
        uint256 claimed = revenue.claimFor(address(asset), alice) + revenue.claimFor(address(asset), bob);
        assertLe(claimed, 2 * yield + cost);
        assertLe(2 * yield + cost - claimed, 1);
        assertEq(revenue.totalTradeDeposited(address(asset)), cost);
        assertEq(revenue.totalTradeClaimed(address(asset)), cost);
        assertEq(revenue.pendingTradeProceeds(alice), 0);
        assertEq(euroToken.balanceOf(address(trade)), 0);
        assertEq(euroToken.balanceOf(address(revenue)), 2 * yield + cost - claimed);
    }
}
