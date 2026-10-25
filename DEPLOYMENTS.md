# Juvantia Smart Contract Deployments

## Current Chiado release without ServicePayments — 2026-10-25

The canonical stack is deployed on Gnosis Chiado (chain ID 10200) from source
`7b9da11`. All **27 deployment/configuration transactions succeeded**, in blocks
23685330–23685490. Independent RPC checks confirm all **14 compiled runtimes**
and **47 ownership, dependency, role, token-decimal and ERC-1967 implementation bindings**.

The [canonical registry](deployments/chiado-10200/deployment.json) records every address,
creation transaction/block, receipt block hash, runtime SHA-256 and configuration receipt.
The adjacent `abi/` directory contains the ten matching integration ABIs. There is no
ServicePayments address or ABI in the current release.

The payer now approves exact gross to Distributor and calls `payInvoice(invoice, signature)`
directly. Distributor checks the payer and authorized Core signature. EIP-712 domain version
is **2**; Invoice contains Payment and payer, without the old source field. Bit 2 is
`SIGNED_INVOICE_ROLE`, available only after signature verification and never an address grant.
Other registered source roles remain TradeHub=1, Consortium=4, Syndicate=8 and Aerarium=16.
`payInvoiceFor` and the service adapter are removed. Core verifies one full Distributor
Settlement inside the exact successful UserOperation; its log index identifies the entitlement.

Distributor is non-upgradeable, Aerarium binds it once, and factory dependencies bind it too.
This is a fresh complete stack, with no UUPS storage reordering or automatic economic migration.
Read-only checks before cutover found zero assets, orders, Consortia, Syndicates, held EURO,
published rules, service requests, service payment operations and entitlements in the old stack.
Earlier public evidence, including addresses for all fifteen old components, their ABIs and source checks,
is preserved in [the archive](deployments/archive/chiado-10200-23669346/deployment.json) and its
[explorer record](deployments/archive/chiado-10200-23669346/explorer-verification.json).
The [earlier release document](https://github.com/juvantia/contract/blob/1cc25d7/DEPLOYMENTS.md)
records the historical adapter deployment. Those addresses are no longer the canonical stack.

## Authorities and payment asset

- Initial owner/deployer: `0x3bb6869ad55fe8890de15ec8a8d8d0ac7994efd1`, encrypted Foundry account `juvantia_admin`.
- Core invoice issuer and both factory authorizers: `0x5002d9895e30a097d69dd64e98899158eb1c7610` (the same existing service key).
- Payment token: `0x7a47605930002cc2cd2c3c408d1f33fc2a18ab71`; actual on-chain decimals: `18`. No symbol was queried.
- Tribunal remains explicitly zero in Distributor, Fabrica and both community factories.

Core signs off chain and has no citizen, owner or Tribunal authority. Users sign their own
wallet operations. Both Core signing settings contain the same server-only key; no key or
environment contents are published here. The temporary deployer password file was removed
after receipt/runtime/binding verification. No new signing key was generated for this cutover.

## Canonical contract addresses

Verified at block `23685490`, hash `0xcd6524f52bf5e3c41c58c76f9eef025212291e381acb64b2ec62a606616ece66`.
Use entry-point proxy addresses for Fabrica, TradeHub and both community factories.

| Role | Address | Creation block | Creation transaction |
| --- | --- | ---: | --- |
| aerarium | `0x3c2e7fa73007792841becb738f07c3ada21368fb` | 23685330 | `0xf3767d7b18ebe133cf7bc1b3f2b1afa078c978a72374317360b98f5188fd505a` |
| revenue | `0x219cbf58baa72423f101c7b96f874bfbd098890b` | 23685332 | `0xe0021544a924a7ac4e41272dc06e74e38fe0780279533abb3a3bc65b8132833e` |
| registry | `0xb7ff921e0800d462afc9dc4540ab9b5770475499` | 23685333 | `0x9ecb08a3a27d12c3c036130a2e4ee3be59e2ade73178b671b292edd343c328e3` |
| assetImplementation | `0x400a240d2598bfbbc7eba28736e2922512bd4b5f` | 23685356 | `0xc8439e0d97c201313a6f068cd8aebb9af8986b103f9df289e230457b5031a9dd` |
| fabricaImplementation | `0x712f3ca3524d122664235d18d907fcd7c38611e9` | 23685366 | `0x6d73aac8421683e2b4d41bfb53216fcb4069831786585d62323732ee92020306` |
| fabrica | `0x3e1b476da33a7698311346fadf22536d8a77776d` | 23685368 | `0x77aaed39d0bece9b17aac1116ac8933df357dd415c9e964bec7ed47967070eec` |
| tradeImplementation | `0x16919989fd17674e157ac6c68e1d57547ec7e051` | 23685383 | `0x5538eb521f9acc8f2e2188c9ef100e037704f13350b3f6587dc94325a447e8f6` |
| trade | `0x1c90a4aa8ab49214493770a36f72706a1cd1d5c4` | 23685397 | `0xe370c93c4b955849b4e27c123056cba0298ce0600f1dc42e64ea6997c6a1b1da` |
| consortiumImplementation | `0x7f1f200786b41faeaaa8bacf08eafac4abcfa4df` | 23685412 | `0xe365d595a3904d2a95ada9d048e7207358d423f5dd086409b75a79f04cb8b83c` |
| consortiumFactoryImplementation | `0x2a4a542e33d030262ff21a4313d70d64a0d1c54a` | 23685416 | `0x604e5d70122ad85d5c60c8385dd78d34917a408b9148782c201fd17d71687016` |
| consortiumFactory | `0x70d73f1d9cb89056bf1720ec37d0d1fbe1194fc6` | 23685426 | `0xbffbe553a9ef6af87647c7af9759c961e3b5e55ecbe5e3fbe21821a0f37f6932` |
| syndicateImplementation | `0x9c0611cadb72c9c3cbf1bfbb79d6f57e24615c30` | 23685448 | `0xb3e45265503858196d3589109fc138da48f7ecc47ee049e4fdd4dc3583a5d64c` |
| syndicateFactoryImplementation | `0x6f892ca88f1679702926cbd5c05f9767cf4bb265` | 23685461 | `0x3166b179cfb1a0aba0f1b84752ff96faac8ebc4f55db8fb58b78b4808b7a2ed2` |
| syndicateFactory | `0xb35ee137adb60de751ee7508853859671cff39ae` | 23685469 | `0xd4654ab9f13d3db526fc211372886bc8016b0c817672f7d226d9b8745892cd05` |

## Explorer source verification

All fourteen addresses have publicly verified sources and contract names through Blockscout's
Sourcify path. Verified at `2026-10-25T14:02:25.349709+00:00` UTC. The
[per-address evidence](deployments/chiado-10200/explorer-verification.json) includes explorer
links, names, proxy types and implementation links. The exact original creation bytecode was
recompiled from compiler metadata before submission.

Each of the four entry points is named `ERC1967Proxy`; its linked implementation is separately
verified as the relevant Juvantia contract. All four links match the verified ERC-1967 slots.

- [JuvantiaRevenueDistributor](https://gnosis-chiado.blockscout.com/address/0x219cbf58baa72423f101c7b96f874bfbd098890b?tab=contract)
- [JuvantiaPaymentRegistry](https://gnosis-chiado.blockscout.com/address/0xb7ff921e0800d462afc9dc4540ab9b5770475499?tab=contract)
- [JuvantiaAssetFabrica](https://gnosis-chiado.blockscout.com/address/0x3e1b476da33a7698311346fadf22536d8a77776d?tab=contract)
- [JuvantiaTradeHub](https://gnosis-chiado.blockscout.com/address/0x1c90a4aa8ab49214493770a36f72706a1cd1d5c4?tab=contract)
- [ConsortiumFactory](https://gnosis-chiado.blockscout.com/address/0x70d73f1d9cb89056bf1720ec37d0d1fbe1194fc6?tab=contract)
- [SyndicateFactory](https://gnosis-chiado.blockscout.com/address/0xb35ee137adb60de751ee7508853859671cff39ae?tab=contract)

## Core and native integration

Core revision: [`3e896142ad415d9d553167e6fdee65381bad877e`](https://github.com/juvantia/core/commit/3e896142ad415d9d553167e6fdee65381bad877e).
The [automatic deployment workflow](https://github.com/juvantia/core/actions/runs/40201397882) completed successfully.
Public [integration evidence](deployments/chiado-10200/integration-verification.json) records the checks.
Post-deployment checks confirmed the expected source/image, a running container with zero
restarts, matching canonical addresses and service identity, no retired adapter setting, and
private configuration present only at runtime. The saved server environment has mode 600;
GitHub `ENV_CORE` is the persistent deployment source.

Public trade reading returned HTTP 200 with zero orders; an unauthenticated profile request
returned HTTP 401. These are read/authentication checks, not paid lifecycle acceptance.

Core settings map to roles in deployment.json as follows:

| Core setting | Canonical role |
| --- | --- |
| PAYMENT_REGISTRY_ADDRESS | registry |
| REVENUE_DISTRIBUTOR_ADDRESS | revenue |
| TRADE_HUB_ADDRESS | trade |
| AERARIUM_ADDRESS | aerarium |
| CONSORTIUM_FACTORY_ADDRESS | consortiumFactory |
| SYNDICATE_FACTORY_ADDRESS | syndicateFactory |

`SERVICE_PAYMENTS_ADDRESS` is removed. Both private signing settings and both public signing
roles retain the same existing Core identity. `COMMUNITY_CREATION_ENABLED=false` remains:
consents, caller authorization, canonical factory receipts and current Consortium voucher
fields must be completed before enabling that deferred workflow.

Native source commit [`79a2092`](https://github.com/juvantia/app/commit/79a2092) validates direct
payInvoice, exact-gross approval and payer/source consistency. Its
[CI](https://github.com/juvantia/app/actions/runs/40175501816) passed. The API envelope is unchanged.
No native binary or OTA was published by this release.

## Verification and reproduction

- 177 Foundry tests pass, including smart-account direct invoices, protected categories,
  issuer revocation, exact charges, funding failure/retry and cross-entry-point replay.
- Solidity 0.8.30, Cancun, optimizer 200, 512 fuzz runs; formatting and build size gates pass.
  Distributor runtime is 20,887 bytes; Syndicate remains 24,357 bytes (219-byte EIP-170 margin).
- 200 Core tests, TypeScript typecheck and SWC build pass.
- 307 native tests, architecture/schema/type/lint/config checks and serial Android/iOS JavaScript exports pass.
- All 60 used Core function/event ABI entries match the verified exported ABIs. A read-only
  signing check confirms Core's EIP-712 digest matches Solidity, domain version 2, and issuer
  authorization. Its deliberately invalid diagnostic invoice cannot settle; no payment was broadcast.

Receipt/runtime verification (with the matching build and raw local broadcast):

```sh
python3 script/verify_deployment.py broadcast/DeployJuvantia.s.sol/10200/run-latest.json deployments/chiado-10200
python3 script/verify_explorer.py deployments/chiado-10200/deployment.json broadcast/DeployJuvantia.s.sol/10200/run-latest.json https://gnosis-chiado.blockscout.com --method sourcify
```

The receipt verifier archives an earlier canonical export before replacement and removes
obsolete current ABIs/explorer evidence. The explorer helper reproduces original compiler
metadata/creation bytecode, skips confirmed publications and records success only after all
names and proxy links match. Neither verifier signs transactions. Raw broadcasts remain local.

`deploy.sh` requires explicit chain/RPC/token/decimals, expected deployer, the two matching
Core public roles and Tribunal. It simulates by default and selects the encrypted account only
for explicit `--broadcast`; skipping simulation or blindly resuming is rejected. Inspect actual
receipts before any recovery. Token decimals are read on chain; supported range is 0–72.

## Remaining activation work

Financial categories/BPS have not been published. The actual Registry owner selects and
publishes them; saving Admin drafts activates nothing. Seller tariffs remain separate from
tax categories. No category list, prices or substitute zero-tax rules were invented.

Real paid invoice/entitlement, rental/Cloud Menu routing, trade, budget/organization settlement
and claimAll acceptance remain separate checks after the intended rules and assets exist.
No EURO payment was made or service entitlement fabricated for deployment verification.
Configure remaining Admin integrations against the canonical stack as required. Native release
authorization and physical-device acceptance remain separate from source/JavaScript checks.
ZeroDev connectivity/gas sponsorship were not retested, as requested by the owner.

See [the direct-invoice review](audit/DIRECT_INVOICES.md),
[payment interfaces](PAYMENT_PROTOCOL.md) and
[Core readiness](../core/docs/DEPLOYMENT_READINESS.md) for scope and deferred workflow limits.
