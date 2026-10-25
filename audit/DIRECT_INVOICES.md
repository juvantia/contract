# Direct invoices — 2026-10-25

Historical review of the ordinary fourteen-component deployment. The 2026-10-26 release adds
UUPS financial proxies while retaining this invoice protocol; see [UPGRADES.md](../UPGRADES.md)
and [current deployment evidence](../DEPLOYMENTS.md). Its original ABI, receipts and runtime
evidence are preserved under `deployments/archive/chiado-10200-23685490/`.

The owner requested removal of JuvantiaServicePayments. Service fulfilment remains off-chain;
the authenticated payment evidence is the Distributor's complete Settlement inside the exact
successful Kernel UserOperation, as required by the Universal Payment Protocol in Notion.

The payer approves exact gross to Distributor and calls payInvoice directly. Invoice now contains
Payment and payer only. The EIP-712 domain version is 2; its type hash excludes the old source
field. Core is still the authorized issuer, and the payer still signs their own wallet operation.
The adapter contract and delegated payInvoiceFor entry point are removed.

Private categories retain bit 2 as SIGNED_INVOICE_ROLE. It applies only after an authorized
invoice signature is verified. No address or registrar can receive bit 2; delegated module roles
remain TradeHub=1, Consortium=4, Syndicate=8 and Aerarium=16. Signed invoices do not grant those
other roles. Public payments and collection retain their existing authorization and accounting.

Verification: all 177 Foundry tests pass, including five new direct-invoice regressions for smart
accounts, exact Settlement/tax/net, forbidden source grants, protected categories, issuer
revocation, missing signatures, atomic funding failure/retry and replay across entry points.
Formatting and size checks pass. Distributor runtime is 20,887 bytes; Syndicate remains 24,357.
Core's 200 tests, typecheck/build and the native client's 307 tests/typecheck/lint pass as well.

Distributor is non-upgradeable. Aerarium is bound once and factories bind Distributor, so this
revision needs a fresh fourteen-component stack, twenty-seven successful deployment/configuration
transactions and matching ABI/address exports. Source checks do not establish activation.
DEPLOYMENTS.md and the canonical registry must change only after receipt/runtime/binding checks.
Keep the earlier deployment and explorer evidence in an archive when replacing the canonical
registry. Do not automatically migrate historical economic state or publish tax categories.

Before cutover, recheck that no assets, organizations, marketplace orders, held EURO or service
payment workflows appeared since the initial read-only empty-state inspection. Preserve the
existing Core service key and zero Tribunal. Switch Core only after the new stack is verified;
remove SERVICE_PAYMENTS_ADDRESS from its local/server/GitHub configuration. Source verification
must also publish and check the new explorer names and proxy implementation links.

The app API envelope is unchanged. Its invoice validator and selector target direct payInvoice;
old adapter calldata fails closed. Native source/JavaScript checks do not publish a binary or OTA.
Deferred organization workflows remain disabled. Financial categories and real paid/device
acceptance remain separate activation work.

## Activation evidence

The replacement is deployed from `7b9da11`: 27 successful receipts, 14 matching runtimes and
47 checked bindings. All fourteen explorer sources/names and four proxy implementation links
are confirmed. The previous thirteen public manifest/ABI/explorer files are archived byte for
byte under `deployments/archive/chiado-10200-23669346/`.

Core `3e89614` was automatically deployed after updating local/server/GitHub configuration.
Runtime file fingerprints, addresses, signer, absence of the adapter setting, mode 600 private
configuration, successful startup and zero restarts are checked. API read/authentication checks
returned 200/401. Core's typed-data digest matches the deployed Solidity domain version 2;
all sixty used ABI entries match. No diagnostic invoice payment was broadcast.

Original receipts, source checks and public runtime evidence are linked in the
[archived deployment](../deployments/archive/chiado-10200-23685490/deployment.json) and
[archived integration verification](../deployments/archive/chiado-10200-23685490/integration-verification.json).
