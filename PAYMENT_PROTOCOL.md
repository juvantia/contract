# Current on-chain payment interface

Business requirements are maintained in [Core PAYMENTS.md](../core/docs/PAYMENTS.md) and
[Universal Payment Protocol](https://app.notion.com/p/3f1fbac38ebd81b9862bd6594308ddb1).
This document describes current Solidity interfaces and their limits, not a catalog of services.

## Requirement and implementation boundary

The seller sets gross price, selects a category and supplies one beneficiary.
The category selects tax BPS only. Core confirms amount/payer without judging the classification;
Custodia reviews classification after payment. No separate settlement commission is required.
A Civitas service named a commission is still an ordinary seller-priced service.

The additional commission configuration, calculation and recipient crediting are removed.
Registry.calculate returns tax and net only. Settlement emits gross, tax and net.
tax = floor(gross * taxBps / 10000), net = gross - tax.
Current Rule still contains servicePrice, destination masks and source permissions.
Category-linked price enforcement remains a separate implementation difference.
Zero servicePrice removes on-chain price enforcement, but Core's current creation-service pricing
then refuses to issue a quote. Implementation alignment is required before activation.
See [current backend differences](../core/docs/PAYMENT_IMPLEMENTATION.md).

No new deployment has been receipt-verified. The reduced Rule tuple and Settlement event require matching ABIs and a fresh configured-stack deployment; no upgrade or on-chain broadcast is performed by this change.

## Settlement and custody

All official non-P2P payments enter Distributor first. Registry revisions are owner-published;
Admin SQL drafts/labels do not activate them. Unknown/inactive categories fail closed.
Explicit zero tax also requires publication. Tax immediately enters Aerarium.
Addressed net is credited to accountRevenue until collection.

The current credit routes are internal accounting details:

- kind 0 credits one beneficiary account.
- kind 1 credits a registered asset's eligible ownership pool.
- kind 2 credits the specific TradeHub seller, with the asset identified separately.

These values are not economic payment categories or invoice delivery methods.
Ordinary seller receipts and a subsequent Consortium owners' allocation are separate operations.
Do not add arbitrary multi-beneficiary sale splits to the clarified protocol.

Pool accounting preserves the O(1) transfer-aware index, fractional remainders, checkpoints,
attributed unsold-share escrow and excluded Consortium treasury shares.
Trade credits remain seller-specific. claimAll(assets) collects account, pool and trade credits;
claimAll([]) collects account-only credits. Existing asset claims remain.
claimAccountFor(account) is permissionless but pays only that beneficiary.
Collection adds no tax. Encumbrance blocks collection; judicial authority remains separate.

## Public and authenticated entry points

Public pay(categoryId,paymentId,gross,kind,destination) debits msg.sender.
A published public category is required; no individual source registration or Core signature
is required for this path. The caller must approve Distributor for the configured token.

```solidity
token.forceApprove(address(distributor), gross); // SafeERC20
distributor.pay(categoryId, paymentId, gross, 0, beneficiary);
```

This example spends the caller's own funds. If a merchant contract collects customer funds and
then calls pay, the merchant contract is the debited payer in Settlement.
This must not be presented as a direct debit of the customer's account.

payFor and payInvoiceFor are available only to registered sources, which must authenticate their
actual payer. Current source roles are TradeHub=1, ServicePayments=2, Consortium=4, Syndicate=8
and Aerarium=16. Factories register permitted instance sources/asset pools.
Registration and source masks control debit authority, not the economic truth of a seller's category.
Do not remove payer authentication when simplifying category semantics.

distributeRevenue and processPayment remain compatibility gateways using published rules.
There is no unclassified zero-tax route or depositTradeProceeds gateway.
Trade buyers authorize Distributor directly; TradeHub holds shares but no withdrawal proceeds.

## Invoices and payment identity

The EIP-712 domain is JuvantiaRevenueDistributor, version 1, selected chain and Distributor address.
Invoice fields are paymentId, categoryId, revision, kind, destination, asset, gross, issuedAt,
expiresAt, payer and source. paymentId identifies the payment; destination separately binds
the beneficiary. The address cannot be inferred from the ID.

The single Core service key signs invoices and factory creation vouchers off chain.
Registry issuer and both factory authorizers use its same public address; see
[Core signing](../core/docs/SIGNING.md). The payer authorizes the actual transaction.
Protecting category/revision from tampering is not a classification approval by Core.
Only Registry-authorized invoice issuers are accepted.

payInvoice authenticates msg.sender as payer and requires source zero.
System service invoices use source ServicePayments; its pay method authenticates msg.sender
as payer and forwards through payInvoiceFor. It holds no funds; approval belongs to Distributor.

A valid issued invoice retains its historical revision until expiry, provided issuedAt falls
within that revision's publication window. Current maximum TTL is seven days.
Issuer revocation can invalidate outstanding invoices. Unsigned pay uses the current revision.
Replay protection is keyed by payer/paymentId across categories.

The seller's service/order record must establish beneficiary, amount and chosen category before
invoice issuance. A generalized verified seller association and organization-payer path are not
implemented merely by accepting destination/payer fields.

For device services, [Core's leasing domain](../core/docs/LEASING.md) resolves earning rights:
a published renter_id selects its verified physical-person account (kind 0), otherwise the
registered owners' pool (kind 1). Leasing maintains that field at the agreed minute boundaries;
service recipient selection does not recheck lease payments/dates. All payments under a Core
rental agreement always credit its owners' pool, independent of current renter/operator or
payment time. Core signs these destinations; Distributor does not read off-chain leases.
Existing account/pool methods support these outcomes. Core menu issuance
resolves the published renter account or owners' pool under a shared device transaction lock.
Scheduled renter-state publication, accepted agreement snapshots, recipient selection and immutable
invoice retries are implemented; [live acceptance](../core/docs/PAYMENT_TODO.md) remains after activation. Issued invoices keep their signed
destination through a handover; no recipient is inferred from paymentId or operator identity.

## Organization operations and existing principal routes

The factory creates the organization's contract address at incorporation. That established
address receives the organization's commercial net; the representative does not assign it.
Owners elect the representative on chain, and the organization contract enforces spending
authority. A new representative retains the same organization address. The Consortium share
token is a separate factory-created contract, not its operating account.

Consortium receives addressed commercial net into its operating funds.
Its separate governed allocation approves gross and reserves net for eligible owners inside
Distributor. The allocation has its own operation tax. Treasury shares are excluded.
totalAllocated measures gross. There is no local Consortium owner payout or duplicate earnings index.
Collecting existing organization credits adds no tax.

Current trade orders preserve their revision for seven days; financial Consortium proposals for
their 36-hour deadline. A private treasury sale is executed by its approved buyer, not by a vote
that debits an arbitrary buyer. The public treasury-listing wrapper remains unimplemented.

Existing refundable Syndicate quota and judicial principal routes require published private
zero-charge rules to preserve their full-principal obligations. These are current domain-specific
mechanisms. A general commercial refund policy is outside the clarified scope.

## Receipts and release

Settlement emits paymentId, debited payer, beneficiary, source, category/revision, route/asset
and actual gross/tax/net. Gross equals tax plus net.

Core service confirmation verifies the exact successful ERC-4337 UserOperation/canonical receipt,
atomic Kernel calldata, and matching ServicePaid/Settlement within its log interval.
A bare transfer, supplied hash or paid flag is insufficient. Service fulfilment stays in its domain.
Confirmed receipts provide audit; no permanent universal indexer is implied.

Contract wiring and receipt-verified deployment records belong to [DEPLOYMENTS.md](DEPLOYMENTS.md).
Backend implementation/readiness belongs to [Core readiness](../core/docs/DEPLOYMENT_READINESS.md).
The category/rate catalog remains administrator data and is not enumerated in this interface.
