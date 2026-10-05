// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {Syndicate} from "../src/community/Syndicate.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAssetFabrica} from "../src/JuvantiaAssetFabrica.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";

contract DeployJuvantia is Script {
    function run() external {
        require(block.chainid == vm.envUint("BLOCKCHAIN_CHAIN_ID"), "Unexpected blockchain");
        address euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        JuvantiaAerarium aerarium = new JuvantiaAerarium(euroToken, deployer);
        JuvantiaRevenueDistributor revenue = new JuvantiaRevenueDistributor(euroToken, deployer, address(aerarium));
        JuvantiaPaymentRegistry registry = new JuvantiaPaymentRegistry(deployer);
        revenue.setPaymentRegistry(address(registry));
        aerarium.configureSettlement(address(registry), address(revenue));
        revenue.setPaymentSource(address(aerarium), 16);
        registry.setInvoiceIssuer(vm.envAddress("PAYMENT_INVOICE_ISSUER_ADDRESS"), true);
        JuvantiaAsset assetImpl = new JuvantiaAsset();
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(assetImpl));
        JuvantiaAssetFabrica fabrica = JuvantiaAssetFabrica(
            address(
                new ERC1967Proxy(
                    address(factoryImpl), abi.encodeCall(JuvantiaAssetFabrica.initialize, (deployer, address(revenue)))
                )
            )
        );
        revenue.setRegistrar(address(fabrica), true);
        JuvantiaTradeHub tradeImpl = new JuvantiaTradeHub();
        address trade = address(
            new ERC1967Proxy(
                address(tradeImpl), abi.encodeCall(JuvantiaTradeHub.initialize, (euroToken, deployer, address(revenue)))
            )
        );
        revenue.setEscrow(trade, true);
        revenue.setPaymentSource(trade, 1);
        JuvantiaServicePayments services = new JuvantiaServicePayments(address(revenue));
        revenue.setPaymentSource(address(services), 2);
        _deployCommunities(euroToken, address(assetImpl), revenue, address(aerarium), deployer);
        address tribunal = vm.envAddress("TRIBUNAL_ADDRESS");
        revenue.setTribunal(tribunal);
        fabrica.setTribunal(tribunal);
        vm.stopBroadcast();

        console.log("Deployer", deployer);
        console.log("JuvantiaPaymentRegistry", address(registry));
        console.log("JuvantiaAerarium", address(aerarium));
        console.log("JuvantiaRevenueDistributor", address(revenue));
        console.log("JuvantiaAsset", address(assetImpl));
        console.log("JuvantiaAssetFabrica implementation", address(factoryImpl));
        console.log("JuvantiaAssetFabrica", address(fabrica));
        console.log("JuvantiaTradeHub implementation", address(tradeImpl));
        console.log("JuvantiaTradeHub", trade);
        console.log("JuvantiaServicePayments", address(services));
    }

    function _deployCommunities(
        address token,
        address assetImpl,
        JuvantiaRevenueDistributor revenue,
        address budget,
        address admin
    ) private {
        address authorizer = vm.envAddress("COMMUNITY_AUTHORIZER_ADDRESS");
        address tribunal = vm.envAddress("TRIBUNAL_ADDRESS");
        ConsortiumFactory c = ConsortiumFactory(
            address(
                new ERC1967Proxy(
                    address(new ConsortiumFactory(address(new Consortium()), assetImpl, address(revenue), budget)),
                    abi.encodeCall(ConsortiumFactory.initialize, (admin, authorizer))
                )
            )
        );
        c.setTribunal(tribunal);
        revenue.setRegistrar(address(c), true);
        SyndicateFactory s = SyndicateFactory(
            address(
                new ERC1967Proxy(
                    address(new SyndicateFactory(address(new Syndicate()), token, address(revenue))),
                    abi.encodeCall(SyndicateFactory.initialize, (admin, authorizer))
                )
            )
        );
        s.setTribunal(tribunal);
        revenue.setPaymentRegistrar(address(s), 8);
        console.log("ConsortiumFactory", address(c));
        console.log("SyndicateFactory", address(s));
    }
}
