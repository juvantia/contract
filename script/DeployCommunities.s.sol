// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {Syndicate} from "../src/community/Syndicate.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";

contract DeployCommunities is Script {
    function run() external {
        require(block.chainid == vm.envUint("BLOCKCHAIN_CHAIN_ID"), "Unexpected blockchain");
        address euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        address revenueAddress = vm.envAddress("REVENUE_DISTRIBUTOR_ADDRESS");
        address aerariumAddress = vm.envAddress("AERARIUM_ADDRESS");
        address assetImpl = vm.envAddress("ASSET_IMPLEMENTATION_ADDRESS");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address authorizer = vm.envOr("COMMUNITY_AUTHORIZER_ADDRESS", deployer);

        // Deploy Consortium implementation and UUPS Factory
        Consortium consortiumImpl = new Consortium();
        ConsortiumFactory consortiumFactoryImpl = new ConsortiumFactory(
            address(consortiumImpl),
            assetImpl,
            revenueAddress,
            aerariumAddress
        );
        ConsortiumFactory consortiumFactory = ConsortiumFactory(address(new ERC1967Proxy(
            address(consortiumFactoryImpl),
            abi.encodeCall(ConsortiumFactory.initialize, (deployer, authorizer))
        )));
        JuvantiaRevenueDistributor(revenueAddress).setRegistrar(address(consortiumFactory), true);

        // Deploy Syndicate implementation and UUPS Factory
        Syndicate syndicateImpl = new Syndicate();
        SyndicateFactory syndicateFactoryImpl = new SyndicateFactory(
            address(syndicateImpl),
            euroToken
        );
        SyndicateFactory syndicateFactory = SyndicateFactory(address(new ERC1967Proxy(
            address(syndicateFactoryImpl),
            abi.encodeCall(SyndicateFactory.initialize, (deployer, authorizer))
        )));

        address tribunalAddress = vm.envOr("TRIBUNAL_ADDRESS", address(0));
        if (tribunalAddress != address(0)) {
            consortiumFactory.setTribunal(tribunalAddress);
            syndicateFactory.setTribunal(tribunalAddress);
        }

        vm.stopBroadcast();

        console.log("Consortium implementation", address(consortiumImpl));
        console.log("ConsortiumFactory implementation", address(consortiumFactoryImpl));
        console.log("ConsortiumFactory proxy", address(consortiumFactory));
        console.log("Syndicate implementation", address(syndicateImpl));
        console.log("SyndicateFactory implementation", address(syndicateFactoryImpl));
        console.log("SyndicateFactory proxy", address(syndicateFactory));
    }
}
