// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {InfrastructureFixture} from "./InfrastructureFixture.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {PaymentSettlement} from "../src/PaymentSettlement.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {Syndicate} from "../src/community/Syndicate.sol";

contract RevenueUpgradeV2 is JuvantiaRevenueDistributor {
    uint256 public upgradeMarker;

    function initializeV2(uint256 marker) external reinitializer(2) onlyOwner {
        upgradeMarker = marker;
    }
}

contract BudgetUpgradeV2 is JuvantiaAerarium {
    uint256 public upgradeMarker;

    function initializeV2(uint256 marker) external reinitializer(2) onlyOwner {
        upgradeMarker = marker;
    }
}

contract RegistryUpgradeV2 is JuvantiaPaymentRegistry {
    uint256 public upgradeMarker;

    function initializeV2(uint256 marker) external reinitializer(2) onlyOwner {
        upgradeMarker = marker;
    }
}

contract WrongUpgradeUUID {
    function proxiableUUID() external pure returns (bytes32) {
        return bytes32(uint256(1));
    }
}

contract InfrastructureUpgradesTest is ProtocolFixture {
    struct AccrualSnapshot {
        uint256 index;
        uint256 credit;
        uint256 claimed;
    }
    bytes32 private constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    bytes4 private constant INVALID_INITIALIZATION = bytes4(keccak256("InvalidInitialization()"));
    uint256 private constant ISSUER_KEY = 0x1872;
    bytes32 private constant SERVICE = keccak256("SERVICE_ENTITLEMENT");

    function testImplementationsAndInitializedProxiesCannotBeInitializedAgain() public {
        JuvantiaAerarium budgetImpl = new JuvantiaAerarium();
        JuvantiaRevenueDistributor revenueImpl = new JuvantiaRevenueDistributor();
        JuvantiaPaymentRegistry registryImpl = new JuvantiaPaymentRegistry();
        vm.expectRevert(INVALID_INITIALIZATION);
        budgetImpl.initialize(address(euroToken), bob);
        vm.expectRevert(INVALID_INITIALIZATION);
        revenueImpl.initialize(address(euroToken), bob, address(aerarium));
        vm.expectRevert(INVALID_INITIALIZATION);
        registryImpl.initialize(bob);
        vm.expectRevert(INVALID_INITIALIZATION);
        aerarium.initialize(address(euroToken), bob);
        vm.expectRevert(INVALID_INITIALIZATION);
        revenue.initialize(address(euroToken), bob, address(aerarium));
        vm.expectRevert(INVALID_INITIALIZATION);
        registry.initialize(bob);
        assertEq(revenue.owner(), address(this));
        assertEq(aerarium.owner(), address(this));
        assertEq(registry.owner(), address(this));
    }

    function testOnlyOwnerCanUpgradeAndOnlyThroughTheProxy() public {
        address[] memory proxies = _proxies();
        address[] memory implementations = _v2Implementations();
        for (uint256 i; i < proxies.length; i++) {
            address original = _implementation(proxies[i]);
            vm.prank(bob);
            vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", bob));
            UUPSUpgradeable(proxies[i]).upgradeToAndCall(implementations[i], "");
            assertEq(_implementation(proxies[i]), original);
            vm.expectRevert(UUPSUpgradeable.UUPSUnauthorizedCallContext.selector);
            UUPSUpgradeable(original).upgradeToAndCall(implementations[i], "");
        }
    }

    function testInvalidUpgradeTargetsLeaveEveryProxyAndItsStateIntact() public {
        address wrongUUID = address(new WrongUpgradeUUID());
        address[] memory proxies = _proxies();
        for (uint256 i; i < proxies.length; i++) {
            address original = _implementation(proxies[i]);
            vm.expectRevert();
            UUPSUpgradeable(proxies[i]).upgradeToAndCall(bob, "");
            vm.expectRevert();
            UUPSUpgradeable(proxies[i]).upgradeToAndCall(address(euroToken), "");
            vm.expectRevert();
            UUPSUpgradeable(proxies[i]).upgradeToAndCall(wrongUUID, "");
            assertEq(_implementation(proxies[i]), original);
        }
        assertTrue(revenue.registeredAssets(address(asset)));
        assertEq(address(revenue.revenueToken()), address(euroToken));
        assertEq(aerarium.revenueDistributor(), address(revenue));
        assertEq(registry.currentRevision(SERVICE), 1);
    }

    function testUpgradeInitializationFailureRollsBackImplementationAndState() public {
        address original = _implementation(address(revenue));
        RevenueUpgradeV2 next = new RevenueUpgradeV2();
        vm.expectRevert(INVALID_INITIALIZATION);
        revenue.upgradeToAndCall(
            address(next),
            abi.encodeCall(JuvantiaRevenueDistributor.initialize, (address(euroToken), bob, address(aerarium)))
        );
        assertEq(_implementation(address(revenue)), original);
        assertEq(revenue.owner(), address(this));
        assertTrue(revenue.registeredAssets(address(asset)));
    }

    function testDistributorUpgradePreservesEarningsEscrowReplayAndOutstandingInvoice() public {
        _publish("OPERATING_RECEIPT", true, 1, 0, 1200);
        bytes32 paymentId = keccak256("addressed-before-upgrade");
        revenue.pay(keccak256("OPERATING_RECEIPT"), paymentId, 100 ether, 0, bob);
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        JuvantiaTradeHub trade = _trade();
        vm.startPrank(alice);
        asset.approve(address(trade), 100 ether);
        uint256 order = trade.createOrder(address(asset), 100 ether, 1 ether, keccak256("SHARE_TRADE"));
        vm.stopPrank();
        vm.startPrank(bob);
        euroToken.approve(address(revenue), 20 ether);
        trade.fillOrder(order, 20 ether);
        vm.stopPrank();
        registry.setInvoiceIssuer(vm.addr(ISSUER_KEY), true);
        PaymentSettlement.Invoice memory invoice = _invoice();
        bytes32 digest = revenue.hashInvoice(invoice);
        bytes memory signature = _signature(digest);
        AccrualSnapshot memory beforeUpgrade = AccrualSnapshot(
            revenue.cumulativeIndex(address(asset)),
            revenue.accrued(address(asset), alice),
            revenue.claimedIndex(address(asset), alice)
        );
        revenue.setTribunal(carol);
        vm.prank(carol);
        revenue.setEncumbrance(bob, true);

        RevenueUpgradeV2 next = new RevenueUpgradeV2();
        revenue.upgradeToAndCall(address(next), abi.encodeCall(RevenueUpgradeV2.initializeV2, (77)));
        assertEq(RevenueUpgradeV2(address(revenue)).upgradeMarker(), 77);
        assertEq(revenue.owner(), address(this));
        assertEq(address(revenue.revenueToken()), address(euroToken));
        assertEq(address(revenue.paymentRegistry()), address(registry));
        assertEq(address(revenue.aerarium()), address(aerarium));
        assertEq(revenue.accountRevenue(bob), 88 ether);
        assertEq(revenue.claimable(address(asset), alice), 120 ether);
        assertEq(revenue.totalDistributed(address(asset)), 100 ether);
        assertEq(revenue.cumulativeIndex(address(asset)), beforeUpgrade.index);
        assertEq(revenue.accrued(address(asset), alice), beforeUpgrade.credit);
        assertEq(revenue.claimedIndex(address(asset), alice), beforeUpgrade.claimed);
        assertTrue(revenue.paid(address(this), paymentId));
        assertTrue(revenue.registrars(address(fabrica)));
        assertTrue(revenue.registeredAssets(address(asset)));
        assertTrue(revenue.escrows(address(trade)));
        assertEq(revenue.sourceRoles(address(trade)), 1);
        assertEq(revenue.sourceRoles(address(aerarium)), 16);
        assertEq(revenue.escrowedFor(address(asset), alice), 80 ether);
        assertEq(revenue.escrowedBalance(address(asset), address(trade)), 80 ether);
        assertEq(revenue.escrowPositions(address(asset), address(trade), alice), 80 ether);
        assertEq(revenue.tradeProceeds(address(asset), alice), 20 ether);
        assertEq(revenue.pendingTradeProceeds(alice), 20 ether);
        assertEq(revenue.totalTradeDeposited(address(asset)), 20 ether);
        assertEq(revenue.tribunal(), carol);
        assertTrue(revenue.encumbered(bob));
        assertEq(revenue.hashInvoice(invoice), digest);
        vm.expectRevert("Account encumbered");
        revenue.claimAccountFor(bob);
        vm.expectRevert("Already paid");
        revenue.pay(keccak256("OPERATING_RECEIPT"), paymentId, 100 ether, 0, bob);
        vm.startPrank(alice);
        euroToken.approve(address(revenue), invoice.payment.gross);
        revenue.payInvoice(invoice, signature);
        vm.stopPrank();
        assertEq(revenue.accountRevenue(carol), 17 ether);
        // Same inputs exercise the persisted private funding nonce, not just visible mappings.
        revenue.distributeRevenue(address(asset), 100 ether, keccak256("ASSET_REVENUE"));
        address[] memory pools = new address[](1);
        pools[0] = address(asset);
        vm.prank(alice);
        assertEq(revenue.claimAll(pools), 219.98 ether);
        assertEq(revenue.pendingTradeProceeds(alice), 0);
        assertEq(revenue.totalTradeClaimed(address(asset)), 20 ether);
        vm.prank(alice);
        trade.cancelOrder(order);
        assertEq(revenue.escrowedBalance(address(asset), address(trade)), 0);
    }

    function testRegistryUpgradePreservesHistoryIssuersAndHistoricalQuotes() public {
        registry.setInvoiceIssuer(vm.addr(ISSUER_KEY), true);
        vm.warp(100);
        uint256 issuedAt = block.timestamp;
        vm.warp(110);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 1800);
        bytes memory original = abi.encode(registry.getVersion(SERVICE, 1));
        RegistryUpgradeV2 next = new RegistryUpgradeV2();
        registry.upgradeToAndCall(address(next), abi.encodeCall(RegistryUpgradeV2.initializeV2, (88)));
        assertEq(RegistryUpgradeV2(address(registry)).upgradeMarker(), 88);
        assertEq(registry.owner(), address(this));
        assertEq(registry.currentRevision(SERVICE), 2);
        assertEq(abi.encode(registry.getVersion(SERVICE, 1)), original);
        assertTrue(registry.invoiceIssuers(vm.addr(ISSUER_KEY)));
        assertFalse(registry.invoiceIssuers(bob));
        assertEq(registry.currentRule(SERVICE).taxBps, 1800);
        assertEq(registry.quotedRule(SERVICE, 1, issuedAt, 200).taxBps, 0);
        vm.warp(120);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 2300);
        assertEq(registry.currentRevision(SERVICE), 3);
        assertEq(registry.getVersion(SERVICE, 2).supersededAt, 120);
        assertEq(registry.quotedRule(SERVICE, 1, issuedAt, 200).taxBps, 0);
    }

    function testDistributorUpgradePreservesFractionalRemaindersUntilTheyBecomePayable() public {
        vm.prank(alice);
        asset.transfer(bob, 1 ether);
        revenue.distributeRevenue(address(asset), 1, keccak256("ASSET_REVENUE"));
        assertEq(revenue.claimFor(address(asset), alice), 0);
        uint256 fraction = revenue.remainder(address(asset), alice);
        uint256 index = revenue.claimedIndex(address(asset), alice);
        assertGt(fraction, 0);
        revenue.upgradeToAndCall(address(new RevenueUpgradeV2()), "");
        assertEq(revenue.remainder(address(asset), alice), fraction);
        assertEq(revenue.claimedIndex(address(asset), alice), index);
        revenue.distributeRevenue(address(asset), 1, keccak256("ASSET_REVENUE"));
        assertEq(revenue.claimFor(address(asset), alice), 1);
        assertEq(euroToken.balanceOf(address(revenue)), 1);
    }

    function testAerariumUpgradePreservesTaxCustodySpentCounterAndAddressedIncome() public {
        _publish("OPERATING_RECEIPT", true, 1, 0, 1000);
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("tax"), 100 ether, 0, bob);
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("budget-receipt"), 40 ether, 0, address(aerarium));
        aerarium.spendReviewed(carol, 5 ether, "equipment", keccak256("BUDGET_EXPENSE"), 1);
        BudgetUpgradeV2 next = new BudgetUpgradeV2();
        aerarium.upgradeToAndCall(address(next), abi.encodeCall(BudgetUpgradeV2.initializeV2, (99)));
        assertEq(BudgetUpgradeV2(address(aerarium)).upgradeMarker(), 99);
        assertEq(aerarium.owner(), address(this));
        assertEq(address(aerarium.revenueToken()), address(euroToken));
        assertEq(address(aerarium.paymentRegistry()), address(registry));
        assertEq(aerarium.revenueDistributor(), address(revenue));
        assertEq(aerarium.totalCollected(), 14 ether);
        assertEq(aerarium.totalSpent(), 5 ether);
        assertEq(euroToken.balanceOf(address(aerarium)), 45 ether);
        assertEq(revenue.accountRevenue(carol), 5 ether);
        aerarium.spendReviewed(carol, 5 ether, "equipment", keccak256("BUDGET_EXPENSE"), 1);
        assertEq(aerarium.totalSpent(), 10 ether);
        assertEq(euroToken.balanceOf(address(aerarium)), 40 ether);
        assertEq(revenue.accountRevenue(carol), 10 ether);
        revenue.pay(keccak256("OPERATING_RECEIPT"), keccak256("tax-after-upgrade"), 100 ether, 0, bob);
        assertEq(aerarium.totalCollected(), 24 ether);
    }

    function testInfrastructureUpgradeLeavesExistingAssetConsortiumAndSyndicateCodeAndStateFixed() public {
        Consortium company = Consortium(Clones.clone(address(new Consortium())));
        JuvantiaAsset shares = JuvantiaAsset(Clones.clone(address(new JuvantiaAsset())));
        company.initialize(
            address(euroToken), address(shares), address(revenue), alice, address(this), address(0), 10, 100
        );
        shares.initialize("Fixed company", "APU", alice, address(this), address(revenue));
        revenue.setRegistrar(address(this), true);
        revenue.registerAsset(address(shares), address(company));
        vm.prank(alice);
        shares.transfer(address(company), 20_000 ether);
        company.depositOperating(200 ether, keccak256("operating"), keccak256("OPERATING_RECEIPT"));
        Syndicate clan = Syndicate(Clones.clone(address(new Syndicate())));
        address[] memory members = new address[](1);
        uint8[] memory grades = new uint8[](1);
        members[0] = bob;
        grades[0] = 2;
        clan.initialize(
            Syndicate.SyndicateInitParams(
                address(euroToken),
                address(revenue),
                alice,
                Syndicate.PresetType(0),
                6,
                members,
                grades,
                address(this),
                address(0)
            )
        );
        bytes32 assetCode = address(asset).codehash;
        bytes32 sharesCode = address(shares).codehash;
        bytes32 companyCode = address(company).codehash;
        bytes32 clanCode = address(clan).codehash;
        address[] memory proxies = _proxies();
        address[] memory implementations = _v2Implementations();
        for (uint256 i; i < proxies.length; i++) {
            UUPSUpgradeable(proxies[i]).upgradeToAndCall(implementations[i], "");
        }
        assertEq(address(asset).codehash, assetCode);
        assertEq(address(shares).codehash, sharesCode);
        assertEq(address(company).codehash, companyCode);
        assertEq(address(clan).codehash, clanCode);
        assertEq(company.magister(), alice);
        assertEq(company.pettyLimit(), 10);
        assertEq(company.majorLimit(), 100);
        assertEq(company.operatingBalance(), 200 ether);
        assertEq(shares.balanceOf(alice), 80_000 ether);
        assertEq(shares.balanceOf(address(company)), 20_000 ether);
        assertEq(revenue.revenueTreasuries(address(shares)), address(company));
        assertEq(revenue.sourceRoles(address(company)), 4);
        assertEq(clan.primus(), alice);
        assertEq(clan.memberCount(), 2);
        assertTrue(clan.isMember(bob));
        assertEq(clan.memberGrades(bob), 2);
        bytes memory update = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", implementations[0], bytes(""));
        (bool assetChanged,) = address(asset).call(update);
        (bool companyChanged,) = address(company).call(update);
        (bool clanChanged,) = address(clan).call(update);
        assertFalse(assetChanged);
        assertFalse(companyChanged);
        assertFalse(clanChanged);
    }

    function _proxies() private view returns (address[] memory proxies) {
        proxies = new address[](3);
        proxies[0] = address(revenue);
        proxies[1] = address(aerarium);
        proxies[2] = address(registry);
    }

    function _v2Implementations() private returns (address[] memory implementations) {
        implementations = new address[](3);
        implementations[0] = address(new RevenueUpgradeV2());
        implementations[1] = address(new BudgetUpgradeV2());
        implementations[2] = address(new RegistryUpgradeV2());
    }

    function _implementation(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    function _trade() private returns (JuvantiaTradeHub trade) {
        trade = JuvantiaTradeHub(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaTradeHub()),
                    abi.encodeCall(JuvantiaTradeHub.initialize, (address(euroToken), address(this), address(revenue)))
                )
            )
        );
        revenue.setEscrow(address(trade), true);
        revenue.setPaymentSource(address(trade), 1);
    }

    function _invoice() private view returns (PaymentSettlement.Invoice memory) {
        return PaymentSettlement.Invoice(
            PaymentSettlement.Payment(
                keccak256("pre-upgrade-invoice"),
                SERVICE,
                1,
                0,
                carol,
                address(0),
                17 ether,
                block.timestamp,
                block.timestamp + 1 hours
            ),
            alice
        );
    }

    function _signature(bytes32 digest) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ISSUER_KEY, digest);
        return abi.encodePacked(r, s, v);
    }
}
