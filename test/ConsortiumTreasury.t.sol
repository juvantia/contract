// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {ConsortiumTreasury} from "../src/community/ConsortiumTreasury.sol";

/// @dev Test-only authority stands in for the still-required Consortium governance layer.
contract ConsortiumTreasuryHarness is ConsortiumTreasury {
    address public harnessAuthority;
    modifier authorized() {
        require(msg.sender == harnessAuthority, "Not authorized");
        _;
    }

    function initialize(address token, address shares, address distributor, address authority) external initializer {
        _initializeTreasury(token, shares, distributor);
        harnessAuthority = authority;
    }

    function allocate(uint256 amount) external authorized nonReentrant {
        _allocateDistributable(amount);
    }

    function spend(address recipient, uint256 amount) external authorized nonReentrant {
        _spendOperating(recipient, amount, keccak256("invoice"));
    }

    function claimDeviceRevenue(address asset) external authorized nonReentrant returns (uint256) {
        return _claimDeviceRevenue(asset);
    }

    function transferTreasuryShares(address recipient, uint256 amount) external authorized {
        shareToken.transfer(recipient, amount);
    }

    function listTreasuryShares(JuvantiaTradeHub hub, uint256 amount) external authorized returns (uint256) {
        shareToken.approve(address(hub), amount);
        return hub.createOrder(address(shareToken), amount, 1 ether);
    }

    function withdrawProceeds(JuvantiaTradeHub hub) external authorized {
        hub.withdraw();
    }
}

contract ConsortiumTreasuryTest is ProtocolFixture {
    ConsortiumTreasuryHarness internal company;
    JuvantiaAsset internal shares;
    JuvantiaTradeHub internal hub;

    function setUp() public override {
        super.setUp();
        shares = JuvantiaAsset(Clones.clone(address(new JuvantiaAsset())));
        company = ConsortiumTreasuryHarness(Clones.clone(address(new ConsortiumTreasuryHarness())));
        company.initialize(address(euroToken), address(shares), address(revenue), address(this));
        shares.initialize("Consortium shares", "APU", address(company), address(this), address(revenue));
        revenue.setRegistrar(address(this), true);
        revenue.registerAsset(address(shares), address(company));
        company.transferTreasuryShares(alice, 60_000 ether);
        company.transferTreasuryShares(bob, 20_000 ether);
        euroToken.approve(address(company), type(uint256).max);
        company.depositOperating(1_000 ether, keccak256("revenue"));
        hub = JuvantiaTradeHub(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaTradeHub()),
                    abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue)))
                )
            )
        );
        revenue.setEscrow(address(hub), true);
        vm.startPrank(bob);
        euroToken.approve(address(hub), type(uint256).max);
        vm.stopPrank();
    }

    function testFixedSharesAndTreasuryExclusion() public {
        assertEq(shares.totalSupply(), 100_000 ether);
        assertEq(company.treasuryShares(), 20_000 ether);
        assertEq(company.circulatingSupply(), 80_000 ether);
        company.allocate(80 ether);
        assertEq(company.claimable(alice), 60 ether);
        assertEq(company.claimable(bob), 20 ether);
        assertEq(company.claimable(address(company)), 0);
        assertEq(company.operatingBalance(), 920 ether);
        assertEq(company.distributablePool(), 80 ether);
    }

    function testFormerHolderKeepsDividendsAfterFullTransfer() public {
        company.allocate(80 ether);
        vm.prank(alice);
        shares.transfer(carol, 60_000 ether);
        assertEq(company.claimFor(carol), 0);
        assertEq(company.claimFor(alice), 60 ether);
        company.allocate(160 ether);
        assertEq(company.claimFor(carol), 120 ether);
        assertEq(company.claimFor(alice), 0);
        assertEq(company.claimFor(bob), 60 ether);
        assertEq(company.totalClaimed(), 240 ether);
        assertEq(company.operatingBalance(), 760 ether);
    }

    function testTreasuryContributionPreservesPriorEarnings() public {
        company.allocate(80 ether);
        vm.prank(alice);
        shares.transfer(address(company), 20_000 ether);
        assertEq(company.treasuryShares(), 40_000 ether);
        company.allocate(60 ether);
        assertEq(company.claimFor(alice), 100 ether);
        assertEq(company.claimFor(bob), 40 ether);
        assertEq(company.claimable(address(company)), 0);
    }

    function testTreasuryBuyerCannotClaimBeforePurchaseRevenue() public {
        company.allocate(80 ether);
        company.transferTreasuryShares(carol, 20_000 ether);
        assertEq(company.claimFor(carol), 0);
        company.allocate(100 ether);
        assertEq(company.claimFor(carol), 20 ether);
        assertEq(company.claimFor(alice), 120 ether);
        assertEq(company.claimFor(bob), 40 ether);
    }

    function testOperatingSpendingCannotTouchAllocatedDividends() public {
        company.allocate(800 ether);
        vm.expectRevert("Insufficient operating funds");
        company.spend(carol, 201 ether);
        company.spend(carol, 200 ether);
        assertEq(company.operatingBalance(), 0);
        assertEq(company.claimFor(alice), 600 ether);
        assertEq(company.claimFor(bob), 200 ether);
        assertEq(euroToken.balanceOf(address(company)), 0);
    }

    function testDirectTransfersAndDeviceClaimForNeedNoSyncOrIndexer() public {
        euroToken.transfer(address(company), 11 ether);
        assertEq(company.operatingBalance(), 1_011 ether);
        vm.prank(alice);
        asset.transfer(address(company), 100_000 ether);
        revenue.distributeRevenue(address(asset), 7 ether);
        revenue.claimFor(address(asset), address(company));
        assertEq(company.operatingBalance(), 1_018 ether);
        revenue.distributeRevenue(address(asset), 5 ether);
        assertEq(company.claimDeviceRevenue(address(asset)), 5 ether);
        assertEq(company.operatingBalance(), 1_023 ether);
        vm.expectRevert("No revenue claimed");
        company.claimDeviceRevenue(address(asset));
    }

    function testSellerEarnsWhileSharesAreListedAndBuyerOnlyAfterFill() public {
        vm.startPrank(alice);
        shares.approve(address(hub), 1_000 ether);
        uint256 order = hub.createOrder(address(shares), 1_000 ether, 1 ether);
        vm.stopPrank();
        company.allocate(80 ether);
        assertEq(company.claimable(address(hub)), 0);
        vm.prank(bob);
        hub.fillOrder(order, 500 ether);
        company.allocate(80 ether);
        assertEq(company.claimFor(alice), 119.5 ether);
        assertEq(company.claimFor(bob), 40.5 ether);
        vm.prank(alice);
        hub.cancelOrder(order);
        assertEq(company.claimable(address(hub)), 0);
        assertEq(company.totalClaimed(), company.totalAllocated());
    }

    function testListedTreasurySharesRemainExcludedUntilSold() public {
        uint256 order = company.listTreasuryShares(hub, 1_000 ether);
        assertEq(shares.balanceOf(address(company)), 19_000 ether);
        assertEq(company.treasuryShares(), 20_000 ether);
        assertEq(company.circulatingSupply(), 80_000 ether);
        company.allocate(80 ether);
        vm.prank(bob);
        hub.fillOrder(order, 1_000 ether);
        assertEq(company.circulatingSupply(), 81_000 ether);
        company.withdrawProceeds(hub);
        assertEq(company.operatingBalance(), 1_920 ether);
        company.allocate(81 ether);
        assertEq(company.claimFor(alice), 120 ether);
        assertEq(company.claimFor(bob), 41 ether);
        assertEq(company.claimable(address(company)), 0);
        assertEq(company.claimable(address(hub)), 0);
    }

    function testFractionsSurviveClaimsAndTransferCheckpoints() public {
        company.allocate(1);
        assertEq(company.claimFor(alice), 0);
        vm.prank(alice);
        shares.transfer(alice, 1);
        company.allocate(3);
        assertEq(company.claimFor(alice), 3);
        assertEq(company.claimFor(bob), 1);
        assertEq(company.distributablePool(), 0);
    }

    function testUnauthorizedHooksAndAllocationRejected() public {
        vm.prank(alice);
        vm.expectRevert("Not distributor");
        company.checkpointAccount(bob);
        vm.prank(alice);
        vm.expectRevert("Not authorized");
        company.allocate(1 ether);
        vm.prank(alice);
        vm.expectRevert("Not authorized");
        company.spend(alice, 1 ether);
        vm.expectRevert("Already registered");
        revenue.registerAsset(address(shares), address(company));
        vm.expectRevert("Observer asset mismatch");
        revenue.registerAsset(address(asset), address(company));
    }

    function testNoDistributionWhenAllSharesAreTreasury() public {
        vm.prank(alice);
        shares.transfer(address(company), 60_000 ether);
        vm.prank(bob);
        shares.transfer(address(company), 20_000 ether);
        vm.expectRevert("No circulating shares");
        company.allocate(1 ether);
        assertEq(company.operatingBalance(), 1_000 ether);
    }

    function testCloneCannotBeInitializedAgain() public {
        vm.expectRevert();
        company.initialize(address(euroToken), address(shares), address(revenue), bob);
        ConsortiumTreasuryHarness implementation = new ConsortiumTreasuryHarness();
        vm.expectRevert();
        implementation.initialize(address(euroToken), address(shares), address(revenue), bob);
    }

    function testUnboundLedgerCannotAllocateDividends() public {
        ConsortiumTreasuryHarness unbound =
            ConsortiumTreasuryHarness(Clones.clone(address(new ConsortiumTreasuryHarness())));
        unbound.initialize(address(euroToken), address(asset), address(revenue), address(this));
        euroToken.transfer(address(unbound), 1 ether);
        vm.expectRevert("Missing treasury checkpoint");
        unbound.allocate(1 ether);
    }

    function testTransferFromKeepsPreviouslyEarnedDividends() public {
        company.allocate(80 ether);
        vm.prank(alice);
        shares.approve(carol, 60_000 ether);
        vm.prank(carol);
        shares.transferFrom(alice, carol, 60_000 ether);
        assertEq(company.claimFor(carol), 0);
        assertEq(company.claimFor(alice), 60 ether);
    }

    function testFuzzPoolConservationAcrossTreasuryTransfers(uint96 allocated, uint96 amountMoved) public {
        uint256 amount = bound(uint256(allocated), 1, 400 ether);
        uint256 moved = bound(uint256(amountMoved), 0, 60_000 ether);
        company.allocate(amount);
        vm.prank(alice);
        shares.transfer(carol, moved);
        assertEq(company.claimable(carol), 0);
        company.allocate(amount);
        uint256 paid = company.claimFor(alice) + company.claimFor(bob) + company.claimFor(carol);
        assertLe(paid, 2 * amount);
        assertLe(2 * amount - paid, 3);
        assertEq(company.distributablePool(), 2 * amount - paid);
        assertEq(company.operatingBalance(), 1_000 ether - 2 * amount);
        assertEq(euroToken.balanceOf(address(company)), company.operatingBalance() + company.distributablePool());
    }
}
