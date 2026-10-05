# Juvantia settlement protocol

All official non-P2P euro payments enter JuvantiaRevenueDistributor first. The non-upgradeable
JuvantiaPaymentRegistry supplies versioned, owner-published rules. PostgreSQL stores administrative
drafts and labels; it cannot activate a financial rule. Unknown/inactive types fail closed. Zero tax
is valid only when explicitly published. Gross includes tax and percentage/fixed commission:
`tax=floor(gross*taxBps/10000)`, `commission=floor(gross*commissionBps/10000)+fixedCommission`,
`net=gross-tax-commission`. Insufficient gross reverts atomically. A fixed civic service price is
separate from commission and, when nonzero, must equal gross.

Tax goes immediately to Aerarium. Commission and addressed net remain in Distributor's
`accountRevenue(account)`. Asset net uses the existing transfer-aware O(1) index: no shareholder
loop, unchanged remainder/checkpoint mathematics, attributed share escrow and excluded Consortium
treasury shares. Trade net remains seller-specific in its separate asset ledger. `claimAll(assets)`
withdraws addressed credits plus pooled earnings and trade proceeds; existing asset claims remain.
`claimAccountFor(account)` is permissionless but pays only the beneficiary. Encumbrance also blocks
addressed claims; Tribunal can reassign these credits with `judicialClaimAccount`.

## Integration

Custom contracts need no individual registration. They fund their own balance, approve Distributor
for exact gross, and use a published public commercial type:

```solidity
token.approve(address(distributor), gross);
distributor.pay(categoryId, uniquePaymentId, gross, 0, recipient); // account
// kind=1 targets a registered asset pool
```

They cannot debit someone else's allowance or use private system categories. Source roles are
owner-configured: TradeHub=1, ServicePayments=2, Consortium=4, Syndicate=8, Aerarium=16. Validated
Consortium registration binds role 4; the configured Syndicate factory registers role 8. Revoking
an escrow/source prevents new settlement without preventing cancellation or collecting old credits.
`distributeRevenue` and `processPayment` are compatibility gateways to published rules, with no
permissionless unclassified zero-tax path. `depositTradeProceeds` is removed.

Trade buyers approve Distributor, which pulls directly from the authenticated buyer. Orders freeze
the current SHARE_TRADE revision and expire after seven days. Consortium sale proposals require
the approved buyer to execute them; a shareholder vote cannot debit an arbitrary buyer. Financial
proposals freeze the rule at creation and use the existing 36-hour proposal deadline.

Consortium allocation is a distinct taxable operation under CONSORTIUM_DISTRIBUTION. Governance
approves gross; totalAllocated measures gross and the owners' pool measures net. Existing device or
trade earnings received by the company become operating funds. Spending and deposits of both
community types also settle centrally; operatingBalance includes pending addressed receipts.
Collecting already accrued funds has no new levy.

Existing cancellable Syndicate quotas/refunds and judicial principal payments require explicitly
published zero-charge private rules. A nonzero charge reverts instead of impairing existing full
principal obligations. Quotas freeze their rule for seven days; an incomplete round can still be
cancelled and refunded. A new refund fiscal policy is intentionally deferred.

## Invoices and evidence

EIP-712 domain: JuvantiaRevenueDistributor, version 1, configured chain ID and Distributor address.
The Invoice fields are paymentId, categoryId, revision, kind, destination, asset, gross, issuedAt,
expiresAt, payer, source (see INVOICE_TYPEHASH). Only published invoice issuer keys are valid.
Core's issuer key signs quotes, never citizen transactions. Source=ServicePayments for system
invoices; the adapter authenticates payer from msg.sender and only emits its receipt. Token
approvals belong to Distributor. A signed invoice binds all fields and is consumable once.
Unexpired issued invoices retain their historical revision, provided issuedAt lies in that
revision's publication window. Maximum quote TTL is seven days. Unsigned pay selects only the
current rule. Key revocation invalidates invoices signed by that key.

Settlement records paymentId, payer, destination, actual source, category/revision, kind, asset,
gross, tax, commission and net. Core checks canonical receipt, exact successful ERC-4337
UserOperation, atomic Kernel calldata, and both ServicePaid and Settlement within that operation's
log interval. A successful transaction or bare ERC-20 transfer cannot grant service rights.
Audit is captured when operations are confirmed; no new permanent indexer is required.

## Coordinated release preparation

DeployJuvantia now prepares Registry, Aerarium, Distributor, asset implementation/factory, TradeHub,
ServicePayments, Consortium/Syndicate implementations and factories, and source/registrar/Tribunal
wiring. Required explicit inputs include BLOCKCHAIN_CHAIN_ID, EURO_TOKEN_ADDRESS,
PAYMENT_INVOICE_ISSUER_ADDRESS, COMMUNITY_AUTHORIZER_ADDRESS and TRIBUNAL_ADDRESS. It publishes no
invented rates or prices: an owner must publish every required category through Admin before
activation. Export receipt-verified ABI/address/deployment blocks, check all bindings and roles,
run paid invoice/trade/governance/claim smoke tests, then configure Core/Admin/native for the same
stack. No existing balances or clones are automatically migrated. Compilation and backend CI do
not establish deployment. DEPLOYMENTS.md changes only after verified receipts.

Arbitrary external ERC-20 transfers cannot be prohibited by this protocol. Official integrations
must use settlement; payment classification and service delivery still require their own business
validation. Routing money alone cannot certify arbitrary code or its off-chain obligations.
