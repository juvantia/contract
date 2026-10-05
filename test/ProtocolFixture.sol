// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAssetFabrica} from "../src/JuvantiaAssetFabrica.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";

contract TestEuroToken is ERC20 {
    constructor() ERC20("Test Euro", "EURO") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

abstract contract ProtocolFixture is Test {
    TestEuroToken internal euroToken;
    JuvantiaAsset internal asset;
    JuvantiaAssetFabrica internal fabrica;
    JuvantiaRevenueDistributor internal revenue;
    JuvantiaAerarium internal aerarium;
    JuvantiaPaymentRegistry internal registry;
    JuvantiaServicePayments internal services;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    function setUp() public virtual {
        euroToken = new TestEuroToken();
        aerarium = new JuvantiaAerarium(address(euroToken), address(this));
        revenue = new JuvantiaRevenueDistributor(address(euroToken), address(this), address(aerarium));
        registry = new JuvantiaPaymentRegistry(address(this));
        revenue.setPaymentRegistry(address(registry));
        aerarium.configureSettlement(address(registry), address(revenue));
        revenue.setPaymentSource(address(aerarium), 16);
        _publish("ASSET_REVENUE", true, 2, 0, 0);
        _publish("LEASING", true, 2, 0, 0);
        _publish("CLOUD_MENU", true, 3, 0, 0);
        _publish("SERVICE_ENTITLEMENT", false, 3, 2, 0);
        _publish("OPERATING_RECEIPT", true, 1, 0, 0);
        _publish("OPERATING_EXPENSE", true, 1, 0, 0);
        _publish("CONSORTIUM_DISTRIBUTION", false, 2, 4, 0);
        _publish("TREASURY_SHARE_SALE", false, 1, 4, 0);
        _publish("SHARE_TRADE", false, 4, 1, 0);
        _publish("BUDGET_EXPENSE", false, 1, 16, 0);
        _publish("SYNDICATE_QUOTA", false, 1, 8, 0);
        _publish("SYNDICATE_REFUND", false, 1, 8, 0);
        _publish("JUDICIAL_PAYMENT", false, 1, 12, 0);
        JuvantiaAsset implementation = new JuvantiaAsset();
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(implementation));
        fabrica = JuvantiaAssetFabrica(
            address(
                new ERC1967Proxy(
                    address(factoryImpl),
                    abi.encodeCall(JuvantiaAssetFabrica.initialize, (address(this), address(revenue)))
                )
            )
        );
        revenue.setRegistrar(address(fabrica), true);
        asset = JuvantiaAsset(fabrica.createAsset(keccak256("asset-1"), "Robulus", alice));
        services = new JuvantiaServicePayments(address(revenue));
        revenue.setPaymentSource(address(services), 2);
        euroToken.mint(address(this), 1_000_000 ether);
        euroToken.approve(address(revenue), type(uint256).max);
        euroToken.mint(alice, 1_000 ether);
        euroToken.mint(bob, 1_000 ether);
    }

    function _publish(string memory category, bool publicAccess, uint8 destinations, uint256 roles, uint16 tax)
        internal
    {
        registry.publish(
            keccak256(bytes(category)),
            JuvantiaPaymentRegistry.Rule(true, publicAccess, destinations, tax, 0, 0, 0, address(0), roles)
        );
    }
}
