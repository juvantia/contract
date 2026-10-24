// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaDeploymentPreflight} from "./DeployJuvantia.s.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {Consortium} from "../src/community/Consortium.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {Syndicate} from "../src/community/Syndicate.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";

/// @notice Add community factories only to an explicitly configured, verified settlement stack.
contract DeployCommunities is JuvantiaDeploymentPreflight {
    struct Deployment {
        address consortiumImplementation;
        address consortiumFactoryImplementation;
        address consortiumFactory;
        address syndicateImplementation;
        address syndicateFactoryImplementation;
        address syndicateFactory;
    }

    function run() external returns (Deployment memory deployed) {
        ReleaseConfiguration memory config = preflight();
        address revenueAddress = vm.envAddress("REVENUE_DISTRIBUTOR_ADDRESS");
        address aerariumAddress = vm.envAddress("AERARIUM_ADDRESS");
        address assetImplementation = vm.envAddress("ASSET_IMPLEMENTATION_ADDRESS");
        _validateExistingStack(config, revenueAddress, aerariumAddress, assetImplementation);

        vm.startBroadcast(config.deployer);
        deployed.consortiumImplementation = address(new Consortium());
        deployed.consortiumFactoryImplementation = address(
            new ConsortiumFactory(
                deployed.consortiumImplementation, assetImplementation, revenueAddress, aerariumAddress
            )
        );
        deployed.consortiumFactory = address(
            new ERC1967Proxy(
                deployed.consortiumFactoryImplementation,
                abi.encodeCall(ConsortiumFactory.initialize, (config.deployer, config.coreSigner))
            )
        );
        ConsortiumFactory(deployed.consortiumFactory).setTribunal(config.tribunal);
        JuvantiaRevenueDistributor(revenueAddress).setRegistrar(deployed.consortiumFactory, true);

        deployed.syndicateImplementation = address(new Syndicate());
        deployed.syndicateFactoryImplementation =
            address(new SyndicateFactory(deployed.syndicateImplementation, config.euroToken, revenueAddress));
        deployed.syndicateFactory = address(
            new ERC1967Proxy(
                deployed.syndicateFactoryImplementation,
                abi.encodeCall(SyndicateFactory.initialize, (config.deployer, config.coreSigner))
            )
        );
        SyndicateFactory(deployed.syndicateFactory).setTribunal(config.tribunal);
        JuvantiaRevenueDistributor(revenueAddress).setPaymentRegistrar(deployed.syndicateFactory, 8);
        vm.stopBroadcast();

        console.log("Verify successful receipts before recording these addresses as canonical.");
        console.log("Consortium implementation", deployed.consortiumImplementation);
        console.log("ConsortiumFactory implementation", deployed.consortiumFactoryImplementation);
        console.log("ConsortiumFactory", deployed.consortiumFactory);
        console.log("Syndicate implementation", deployed.syndicateImplementation);
        console.log("SyndicateFactory implementation", deployed.syndicateFactoryImplementation);
        console.log("SyndicateFactory", deployed.syndicateFactory);
    }

    function _validateExistingStack(
        ReleaseConfiguration memory config,
        address revenueAddress,
        address aerariumAddress,
        address assetImplementation
    ) private view {
        require(
            revenueAddress.code.length > 0 && aerariumAddress.code.length > 0 && assetImplementation.code.length > 0,
            "Invalid existing contracts"
        );
        JuvantiaRevenueDistributor revenue = JuvantiaRevenueDistributor(revenueAddress);
        JuvantiaAerarium budget = JuvantiaAerarium(aerariumAddress);
        require(revenue.owner() == config.deployer, "Distributor owner mismatch");
        require(address(revenue.revenueToken()) == config.euroToken, "Distributor token mismatch");
        require(address(revenue.aerarium()) == aerariumAddress, "Distributor budget mismatch");
        require(revenue.tribunal() == config.tribunal, "Distributor tribunal mismatch");
        require(address(budget.revenueToken()) == config.euroToken, "Budget token mismatch");
        require(budget.revenueDistributor() == revenueAddress, "Budget distributor mismatch");
        require(address(budget.paymentRegistry()) == address(revenue.paymentRegistry()), "Budget registry mismatch");
        require(revenue.paymentRegistry().invoiceIssuers(config.coreSigner), "Core signer not authorized");
    }
}
