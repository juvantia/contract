// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAssetFabrica} from "../src/JuvantiaAssetFabrica.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";

contract TestEuroToken is ERC20 {
    constructor() ERC20("Test Euro", "EURO") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

abstract contract ProtocolFixture is Test {
    TestEuroToken internal euroToken;
    JuvantiaAsset internal asset;
    JuvantiaAssetFabrica internal fabrica;
    JuvantiaRevenueDistributor internal revenue;
    JuvantiaAerarium internal aerarium;
    JuvantiaServicePayments internal services;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    function setUp() public virtual {
        euroToken = new TestEuroToken();
        aerarium = new JuvantiaAerarium(address(euroToken), address(this));
        revenue = new JuvantiaRevenueDistributor(address(euroToken), address(this), address(aerarium));
        JuvantiaAsset implementation = new JuvantiaAsset();
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(implementation));
        fabrica = JuvantiaAssetFabrica(address(new ERC1967Proxy(address(factoryImpl),
            abi.encodeCall(JuvantiaAssetFabrica.initialize, (address(this), address(revenue))))));
        revenue.setRegistrar(address(fabrica), true);
        asset = JuvantiaAsset(fabrica.createAsset(keccak256("asset-1"), "Robulus", alice));
        services = new JuvantiaServicePayments(address(euroToken));
        euroToken.mint(address(this), 1_000_000 ether);
        euroToken.approve(address(revenue), type(uint256).max);
        euroToken.mint(alice, 1_000 ether);
        euroToken.mint(bob, 1_000 ether);
    }
}
