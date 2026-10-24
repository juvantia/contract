// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DeployJuvantia, JuvantiaDeploymentPreflight} from "../script/DeployJuvantia.s.sol";
import {DeployCommunities} from "../script/DeployCommunities.s.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaAssetFabrica} from "../src/JuvantiaAssetFabrica.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";
import {ConsortiumFactory} from "../src/community/ConsortiumFactory.sol";
import {SyndicateFactory} from "../src/community/SyndicateFactory.sol";

contract DeploymentTestEuro is ERC20 {
    uint8 private immutable tokenDecimals;

    constructor(uint8 decimals_) ERC20("Deployment fixture", "TEST") {
        tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }

    function symbol() public pure override returns (string memory) {
        revert("Release must not query symbol");
    }
}

/// @dev Exercises run() with per-instance input, avoiding process-global environment races.
contract ConfiguredDeploymentScript is DeployJuvantia {
    ReleaseInput private input;

    constructor(ReleaseInput memory release) {
        input = release;
    }

    function preflight() public view override returns (ReleaseConfiguration memory) {
        return validateRelease(input);
    }
}

contract DeploymentReadinessTest is Test {
    address private constant OWNER = address(0xD3E10);
    address private constant CORE_SIGNER = address(0xC04E);
    address private constant TRIBUNAL = address(0x791B);
    bytes32 private constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    DeploymentTestEuro private token;
    DeployJuvantia private script;
    JuvantiaDeploymentPreflight.ReleaseInput private input;

    function setUp() public {
        vm.chainId(10200);
        token = new DeploymentTestEuro(6);
        script = new DeployJuvantia();
        input = JuvantiaDeploymentPreflight.ReleaseInput(
            10200, OWNER, address(token), 6, CORE_SIGNER, CORE_SIGNER, TRIBUNAL
        );
    }

    function testFullStackSimulationHasAllBindingsAndSeparateAuthorities() public {
        _setEnvironment();
        DeployJuvantia.Deployment memory d = script.run();
        JuvantiaRevenueDistributor revenue = JuvantiaRevenueDistributor(d.revenue);
        JuvantiaPaymentRegistry registry = JuvantiaPaymentRegistry(d.registry);
        JuvantiaAerarium budget = JuvantiaAerarium(d.aerarium);
        JuvantiaAssetFabrica fabrica = JuvantiaAssetFabrica(d.fabrica);
        JuvantiaTradeHub trade = JuvantiaTradeHub(d.trade);
        ConsortiumFactory cFactory = ConsortiumFactory(d.consortiumFactory);
        SyndicateFactory sFactory = SyndicateFactory(d.syndicateFactory);

        assertEq(revenue.owner(), OWNER);
        assertEq(registry.owner(), OWNER);
        assertEq(budget.owner(), OWNER);
        assertEq(fabrica.owner(), OWNER);
        assertEq(trade.owner(), OWNER);
        assertEq(cFactory.owner(), OWNER);
        assertEq(sFactory.owner(), OWNER);
        assertTrue(registry.invoiceIssuers(CORE_SIGNER));
        assertFalse(registry.invoiceIssuers(OWNER));
        assertEq(cFactory.authorizer(), CORE_SIGNER);
        assertEq(sFactory.authorizer(), CORE_SIGNER);
        assertEq(revenue.tribunal(), TRIBUNAL);
        assertEq(fabrica.tribunal(), TRIBUNAL);
        assertEq(cFactory.tribunal(), TRIBUNAL);
        assertEq(sFactory.tribunal(), TRIBUNAL);

        assertEq(address(revenue.revenueToken()), address(token));
        assertEq(address(revenue.paymentRegistry()), d.registry);
        assertEq(address(revenue.aerarium()), d.aerarium);
        assertEq(address(budget.revenueToken()), address(token));
        assertEq(budget.revenueDistributor(), d.revenue);
        assertEq(address(budget.paymentRegistry()), d.registry);
        assertEq(address(fabrica.revenueDistributor()), d.revenue);
        assertEq(fabrica.assetImplementation(), d.assetImplementation);
        assertEq(address(trade.currencyToken()), address(token));
        assertEq(address(trade.revenueDistributor()), d.revenue);
        assertEq(address(JuvantiaServicePayments(d.services).revenueDistributor()), d.revenue);
        assertEq(JuvantiaServicePayments(d.services).paymentToken(), address(token));
        assertEq(address(cFactory.revenueDistributor()), d.revenue);
        assertEq(address(cFactory.aerarium()), d.aerarium);
        assertEq(cFactory.consortiumImplementation(), d.consortiumImplementation);
        assertEq(cFactory.assetImplementation(), d.assetImplementation);
        assertEq(sFactory.revenueDistributor(), d.revenue);
        assertEq(sFactory.paymentToken(), address(token));
        assertEq(sFactory.syndicateImplementation(), d.syndicateImplementation);

        assertTrue(revenue.registrars(d.fabrica));
        assertTrue(revenue.registrars(d.consortiumFactory));
        assertTrue(revenue.escrows(d.trade));
        assertEq(revenue.sourceRoles(d.aerarium), 16);
        assertEq(revenue.sourceRoles(d.trade), 1);
        assertEq(revenue.sourceRoles(d.services), 2);
        assertEq(revenue.registrarRoles(d.syndicateFactory), 8);
        assertEq(_implementation(d.fabrica), d.fabricaImplementation);
        assertEq(_implementation(d.trade), d.tradeImplementation);
        assertEq(_implementation(d.consortiumFactory), d.consortiumFactoryImplementation);
        assertEq(_implementation(d.syndicateFactory), d.syndicateFactoryImplementation);
        _checkStandaloneCommunities(d);
    }

    function testPreflightReadsActualDecimalsWithoutReadingSymbol() public view {
        JuvantiaDeploymentPreflight.ReleaseConfiguration memory config = script.validateRelease(input);
        assertEq(config.euroTokenDecimals, 6);
        assertEq(config.euroToken, address(token));
        assertEq(config.deployer, OWNER);
        assertEq(config.coreSigner, CORE_SIGNER);
        assertEq(config.tribunal, TRIBUNAL);
    }

    function testWrongChainFailsBeforeAnyDeployment() public {
        input.chainId = 100;
        _expectNoDeployment("Unexpected blockchain");
    }

    function testWrongDecimalsFailBeforeAnyDeployment() public {
        input.euroTokenDecimals = 18;
        _expectNoDeployment("Token decimals mismatch");
    }

    function testUnsupportedTokenDecimalsFailBeforeAnyDeployment() public {
        input.euroToken = address(new DeploymentTestEuro(73));
        input.euroTokenDecimals = 73;
        _expectNoDeployment("Unsupported token decimals");
    }

    function testDifferentCoreSignersFailBeforeAnyDeployment() public {
        input.communityAuthorizer = address(0xBAD);
        _expectNoDeployment("Core signer mismatch");
    }

    function testZeroTribunalFailsBeforeAnyDeployment() public {
        input.tribunal = address(0);
        _expectNoDeployment("Invalid tribunal");
    }

    function testOwnerCannotAlsoBeTheCoreSigner() public {
        input.invoiceIssuer = OWNER;
        input.communityAuthorizer = OWNER;
        _expectNoDeployment("Authorities must be distinct");
    }

    function testTribunalCannotAlsoBeTheCoreSignerOrOwner() public {
        input.tribunal = CORE_SIGNER;
        _expectNoDeployment("Authorities must be distinct");
        input.tribunal = OWNER;
        _expectNoDeployment("Authorities must be distinct");
    }

    function testMissingTokenCodeFailsBeforeAnyDeployment() public {
        input.euroToken = address(0xBAD);
        _expectNoDeployment("Invalid token");
    }

    function testZeroDeployerOrCoreSignerFailsBeforeAnyDeployment() public {
        input.deployer = address(0);
        _expectNoDeployment("Invalid deployer");
        input.deployer = OWNER;
        input.invoiceIssuer = address(0);
        input.communityAuthorizer = address(0);
        _expectNoDeployment("Core signer mismatch");
    }

    function _checkStandaloneCommunities(DeployJuvantia.Deployment memory d) private {
        _setExistingStack(d);
        DeployCommunities communityScript = new DeployCommunities();
        DeployCommunities.Deployment memory c = communityScript.run();
        JuvantiaRevenueDistributor revenue = JuvantiaRevenueDistributor(d.revenue);
        assertTrue(revenue.registrars(c.consortiumFactory));
        assertEq(revenue.registrarRoles(c.syndicateFactory), 8);
        assertEq(ConsortiumFactory(c.consortiumFactory).authorizer(), CORE_SIGNER);
        assertEq(SyndicateFactory(c.syndicateFactory).authorizer(), CORE_SIGNER);
        assertEq(ConsortiumFactory(c.consortiumFactory).tribunal(), TRIBUNAL);
        assertEq(SyndicateFactory(c.syndicateFactory).tribunal(), TRIBUNAL);
        vm.setEnv("TRIBUNAL_ADDRESS", vm.toString(address(0xBAD)));
        uint256 beforeNonce = vm.getNonce(OWNER);
        vm.expectRevert("Distributor tribunal mismatch");
        communityScript.run();
        assertEq(vm.getNonce(OWNER), beforeNonce);
        vm.setEnv("TRIBUNAL_ADDRESS", vm.toString(TRIBUNAL));
    }

    function _expectNoDeployment(string memory reason) private {
        ConfiguredDeploymentScript configuredScript = new ConfiguredDeploymentScript(input);
        uint256 beforeNonce = vm.getNonce(OWNER);
        vm.expectRevert(bytes(reason));
        configuredScript.run();
        assertEq(vm.getNonce(OWNER), beforeNonce);
    }

    // Only the integration test mutates env. vm.setEnv is process-global, unlike EVM state.
    function _setEnvironment() private {
        vm.setEnv("BLOCKCHAIN_CHAIN_ID", vm.toString(input.chainId));
        vm.setEnv("DEPLOYER_ADDRESS", vm.toString(input.deployer));
        vm.setEnv("EURO_TOKEN_ADDRESS", vm.toString(input.euroToken));
        vm.setEnv("EURO_TOKEN_DECIMALS", vm.toString(input.euroTokenDecimals));
        vm.setEnv("PAYMENT_INVOICE_ISSUER_ADDRESS", vm.toString(input.invoiceIssuer));
        vm.setEnv("COMMUNITY_AUTHORIZER_ADDRESS", vm.toString(input.communityAuthorizer));
        vm.setEnv("TRIBUNAL_ADDRESS", vm.toString(input.tribunal));
    }

    function _setExistingStack(DeployJuvantia.Deployment memory d) private {
        vm.setEnv("REVENUE_DISTRIBUTOR_ADDRESS", vm.toString(d.revenue));
        vm.setEnv("AERARIUM_ADDRESS", vm.toString(d.aerarium));
        vm.setEnv("ASSET_IMPLEMENTATION_ADDRESS", vm.toString(d.assetImplementation));
    }

    function _implementation(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }
}
