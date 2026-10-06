# Juvantia Smart Contract Deployments

## Current status — 2026-10-06

There is currently no canonical deployment for the configurable ZeroDev universal-settlement
stack. The user is still selecting the network. No on-chain transactions were broadcast by the
settlement implementation or this documentation update. No deployment addresses/blocks are asserted.

The clarified tax-only, seller-priced model is documented in
[Core PAYMENTS.md](../core/docs/PAYMENTS.md). Additional commissions are removed from source,
ABIs, reviews and public DTOs. Category-linked creation prices and some hardcoded service categories
remain implementation differences. Beneficiary association
and organizational payer identity also require work. These differences are described in
[PAYMENT_IMPLEMENTATION.md](../core/docs/PAYMENT_IMPLEMENTATION.md); they are not fixed by this update.
Activation requires model alignment as well as receipt-verified deployment.

Contract settlement source, tests and the full-stack deployment script are implemented.
Core invoice signing and receipt-based payment integration are implemented; complete Core
readiness remains subject to the documented gaps and live acceptance.

See [PAYMENT_PROTOCOL.md](PAYMENT_PROTOCOL.md), [Core signing](../core/docs/SIGNING.md)
and [Core readiness](../core/docs/DEPLOYMENT_READINESS.md).

## Release configuration

Deployment configuration is supplied at release time through:

- `BLOCKCHAIN_CHAIN_ID`
- `BLOCKCHAIN_RPC_URL`
- `EURO_TOKEN_ADDRESS`
- `EURO_TOKEN_DECIMALS` in the services, checked against the actual token
- `PAYMENT_INVOICE_ISSUER_ADDRESS`: public address derived from Core's invoice service key
- `COMMUNITY_AUTHORIZER_ADDRESS`: public address matching Core's factory-voucher authorizer
- `TRIBUNAL_ADDRESS`: actual Tribunal authority selected for the stack

Core separately receives the server-only PAYMENT_INVOICE_SIGNING_KEY and
COMMUNITY_AUTHORIZER_PRIVATE_KEY secrets. Private keys and production configuration must not
be recorded here. The invoice key only signs off-chain terms; users authorize their own operations.
It needs no token/native balance to sign. Owner/deployer transactions have a separate gas payer.
DeployJuvantia.s.sol already grants the chosen public invoice issuer in Registry.

## Complete deployment inventory

Deploy script: script/DeployJuvantia.s.sol. Prepare and verify the complete set:

- JuvantiaPaymentRegistry, JuvantiaAerarium and JuvantiaRevenueDistributor.
- JuvantiaServicePayments, bound to Distributor.
- JuvantiaAsset implementation and JuvantiaAssetFabrica implementation/proxy.
- JuvantiaTradeHub implementation/proxy.
- Consortium implementation and ConsortiumFactory implementation/proxy.
- Syndicate implementation and SyndicateFactory implementation/proxy.
- Real Tribunal wiring. The script requires the external Tribunal address; it does not
  establish a deployed Tribunal constitution/jury system.

Verify Fabrica and Consortium factory asset registrars; Syndicate factory payment registrar;
TradeHub escrow/source; ServicePayments/Aerarium sources; Consortium/Syndicate instance roles.
Source bits are TradeHub=1, ServicePayments=2, Consortium=4, Syndicate=8 and Aerarium=16.

## Required activation evidence

1. Verify successful deployment/configuration receipts, selected chain ID, real token/decimals,
   proxy implementations and every cross-contract binding.
2. Export real ABIs, addresses and deployment blocks for Core/Admin and other integrations.
3. Publish the administrator's selected tax categories/BPS with the actual Registry owner.
   Saving a draft activates nothing. Seller tariffs belong to seller service configuration,
   not the tax catalog. Include the separately taxed owners' allocation operation.
   Existing private full-principal mechanisms retain their domain requirements.
   No catalog of concrete services/categories is prescribed by this deployment record.
4. Check the permitted issuer and matching Core secret; both factory authorizers must match
   their configured Core service identity. Core keys do not receive owner/Tribunal authority.
5. Resolve the payment-model differences and known Core receipt/consent/configuration/cutover gaps
   in Core readiness before declaring the whole server layer operational.
6. Exercise actual paid invoice/entitlement, civic fee/factory creation, trade, Consortium
   owners' allocation, operating/budget spending, public custom settlement and claimAll receipts.
   Verify the clarified gross = tax + net, the real debited payer and single beneficiary,
   unchanged historical invoices, replay/expiry failure and recovery.

Net is a central credit until collection; tax reaches Aerarium immediately.
Rule tuple and Settlement event signatures changed. Export matching ABIs for all services and
use a fresh configured-stack deployment; the non-upgradeable Registry is not upgraded in place.
Consortium allocation has its own tax; collecting existing credits has no new levy.
TradeHub.pendingWithdrawals is a compatibility read, and TradeHub has no euro withdraw route.

## Canonical receipt record — pending

After a receipt-verified deployment, record the configured blockchain ID,
deployment block, proxy and implementation addresses here. Historical deployment
addresses are intentionally not accepted as defaults by scripts or services.

For each verified deployment/upgrade record chain ID, contract role, address, proxy/implementation
relationship, transaction hash, successful receipt block and source revision. Record owner rule
publication category/revision and issuer/source/registrar configuration evidence as well.
This section contains no records because no new canonical deployment has been verified.

No old clones, balances or economic state migrate automatically. Backend builds/deployments
and Android/iOS JavaScript exports do not establish on-chain activation or a native binary/OTA release.
