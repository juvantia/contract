// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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

/// @dev Shared release checks run before recording any broadcast transaction.
abstract contract JuvantiaDeploymentPreflight is Script {
    struct ReleaseInput {
        uint256 chainId;
        address deployer;
        address euroToken;
        uint256 euroTokenDecimals;
        address invoiceIssuer;
        address communityAuthorizer;
        address tribunal;
    }

    struct ReleaseConfiguration {
        address deployer;
        address euroToken;
        uint8 euroTokenDecimals;
        address coreSigner;
        address tribunal;
    }

    function preflight() public view virtual returns (ReleaseConfiguration memory) {
        ReleaseInput memory input;
        input.chainId = vm.envUint("BLOCKCHAIN_CHAIN_ID");
        input.deployer = vm.envAddress("DEPLOYER_ADDRESS");
        input.euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        input.euroTokenDecimals = vm.envUint("EURO_TOKEN_DECIMALS");
        input.invoiceIssuer = vm.envAddress("PAYMENT_INVOICE_ISSUER_ADDRESS");
        input.communityAuthorizer = vm.envAddress("COMMUNITY_AUTHORIZER_ADDRESS");
        input.tribunal = vm.envAddress("TRIBUNAL_ADDRESS");
        return validateRelease(input);
    }

    function validateRelease(ReleaseInput memory input) public view returns (ReleaseConfiguration memory config) {
        require(block.chainid == input.chainId, "Unexpected blockchain");
        config.deployer = input.deployer;
        config.euroToken = input.euroToken;
        config.coreSigner = input.invoiceIssuer;
        config.tribunal = input.tribunal;

        require(config.deployer != address(0), "Invalid deployer");
        require(config.euroToken.code.length > 0, "Invalid token");
        // The community's largest default amount is 25,000 full tokens.
        require(input.euroTokenDecimals <= 72, "Unsupported token decimals");
        config.euroTokenDecimals = IERC20Metadata(config.euroToken).decimals();
        require(config.euroTokenDecimals == input.euroTokenDecimals, "Token decimals mismatch");
        require(
            config.coreSigner != address(0) && config.coreSigner == input.communityAuthorizer, "Core signer mismatch"
        );
        require(config.tribunal != address(0), "Invalid tribunal");
        require(
            config.deployer != config.coreSigner && config.deployer != config.tribunal
                && config.coreSigner != config.tribunal,
            "Authorities must be distinct"
        );
    }
}

contract DeployJuvantia is JuvantiaDeploymentPreflight {
    /// @dev Simulation output is not a receipt-verified canonical deployment record.
    struct Deployment {
        address registry;
        address aerarium;
        address revenue;
        address assetImplementation;
        address fabricaImplementation;
        address fabrica;
        address tradeImplementation;
        address trade;
        address services;
        address consortiumImplementation;
        address consortiumFactoryImplementation;
        address consortiumFactory;
        address syndicateImplementation;
        address syndicateFactoryImplementation;
        address syndicateFactory;
    }

    function run() external returns (Deployment memory deployed) {
        ReleaseConfiguration memory config = preflight();
        vm.startBroadcast(config.deployer);

        deployed.aerarium = address(new JuvantiaAerarium(config.euroToken, config.deployer));
        deployed.revenue = address(new JuvantiaRevenueDistributor(config.euroToken, config.deployer, deployed.aerarium));
        deployed.registry = address(new JuvantiaPaymentRegistry(config.deployer));
        JuvantiaRevenueDistributor revenue = JuvantiaRevenueDistributor(deployed.revenue);
        revenue.setPaymentRegistry(deployed.registry);
        JuvantiaAerarium(deployed.aerarium).configureSettlement(deployed.registry, deployed.revenue);
        revenue.setPaymentSource(deployed.aerarium, 16);
        JuvantiaPaymentRegistry(deployed.registry).setInvoiceIssuer(config.coreSigner, true);

        deployed.assetImplementation = address(new JuvantiaAsset());
        deployed.fabricaImplementation = address(new JuvantiaAssetFabrica(deployed.assetImplementation));
        deployed.fabrica = address(
            new ERC1967Proxy(
                deployed.fabricaImplementation,
                abi.encodeCall(JuvantiaAssetFabrica.initialize, (config.deployer, deployed.revenue))
            )
        );
        revenue.setRegistrar(deployed.fabrica, true);

        deployed.tradeImplementation = address(new JuvantiaTradeHub());
        deployed.trade = address(
            new ERC1967Proxy(
                deployed.tradeImplementation,
                abi.encodeCall(JuvantiaTradeHub.initialize, (config.euroToken, config.deployer, deployed.revenue))
            )
        );
        revenue.setEscrow(deployed.trade, true);
        revenue.setPaymentSource(deployed.trade, 1);
        deployed.services = address(new JuvantiaServicePayments(deployed.revenue));
        revenue.setPaymentSource(deployed.services, 2);

        _deployCommunities(config, deployed);
        revenue.setTribunal(config.tribunal);
        JuvantiaAssetFabrica(deployed.fabrica).setTribunal(config.tribunal);
        vm.stopBroadcast();

        _logDeployment(config, deployed);
    }

    function _deployCommunities(ReleaseConfiguration memory config, Deployment memory deployed) private {
        deployed.consortiumImplementation = address(new Consortium());
        deployed.consortiumFactoryImplementation = address(
            new ConsortiumFactory(
                deployed.consortiumImplementation, deployed.assetImplementation, deployed.revenue, deployed.aerarium
            )
        );
        deployed.consortiumFactory = address(
            new ERC1967Proxy(
                deployed.consortiumFactoryImplementation,
                abi.encodeCall(ConsortiumFactory.initialize, (config.deployer, config.coreSigner))
            )
        );
        ConsortiumFactory(deployed.consortiumFactory).setTribunal(config.tribunal);
        JuvantiaRevenueDistributor(deployed.revenue).setRegistrar(deployed.consortiumFactory, true);

        deployed.syndicateImplementation = address(new Syndicate());
        deployed.syndicateFactoryImplementation =
            address(new SyndicateFactory(deployed.syndicateImplementation, config.euroToken, deployed.revenue));
        deployed.syndicateFactory = address(
            new ERC1967Proxy(
                deployed.syndicateFactoryImplementation,
                abi.encodeCall(SyndicateFactory.initialize, (config.deployer, config.coreSigner))
            )
        );
        SyndicateFactory(deployed.syndicateFactory).setTribunal(config.tribunal);
        JuvantiaRevenueDistributor(deployed.revenue).setPaymentRegistrar(deployed.syndicateFactory, 8);
    }

    function _logDeployment(ReleaseConfiguration memory config, Deployment memory deployed) private pure {
        console.log("Verify successful receipts before recording these addresses as canonical.");
        console.log("Deployer and initial owner", config.deployer);
        console.log("Configured euro-token decimals", uint256(config.euroTokenDecimals));
        console.log("JuvantiaPaymentRegistry", deployed.registry);
        console.log("JuvantiaAerarium", deployed.aerarium);
        console.log("JuvantiaRevenueDistributor", deployed.revenue);
        console.log("JuvantiaAsset implementation", deployed.assetImplementation);
        console.log("JuvantiaAssetFabrica implementation", deployed.fabricaImplementation);
        console.log("JuvantiaAssetFabrica", deployed.fabrica);
        console.log("JuvantiaTradeHub implementation", deployed.tradeImplementation);
        console.log("JuvantiaTradeHub", deployed.trade);
        console.log("JuvantiaServicePayments", deployed.services);
        console.log("Consortium implementation", deployed.consortiumImplementation);
        console.log("ConsortiumFactory implementation", deployed.consortiumFactoryImplementation);
        console.log("ConsortiumFactory", deployed.consortiumFactory);
        console.log("Syndicate implementation", deployed.syndicateImplementation);
        console.log("SyndicateFactory implementation", deployed.syndicateFactoryImplementation);
        console.log("SyndicateFactory", deployed.syndicateFactory);
    }
}
