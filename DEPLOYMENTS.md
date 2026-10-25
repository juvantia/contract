# Juvantia Smart Contract Deployments

## Current Chiado UUPS infrastructure — 2026-10-26

The owner's requested financial infrastructure is deployed on Gnosis Chiado (chain ID 10200)
from source `9ec8b30`. All **30 deployment/configuration transactions succeeded**
in blocks 23688971–23689121. Independent RPC verification confirms **17 matching
compiled runtimes** and **78 dependency, owner, role, token, proxy and initialization checks**.

Seven permanent entry points use ERC-1967/UUPS: RevenueDistributor, Aerarium, PaymentRegistry,
Fabrica, TradeHub, ConsortiumFactory and SyndicateFactory. Only their current owner can upgrade
their logic. Proxy state and addresses remain in place through compatible upgrades.
Created Asset, Consortium and Syndicate instances retain their original fixed clone code.
Normal membership, voting and permitted settings still follow their creation-time rules.
No beacon or instance-upgrade mechanism was added.

The [canonical registry](deployments/chiado-10200/deployment.json) records all addresses,
creation/configuration receipts, blocks/hashes, runtime SHA-256 and implementation links.
The adjacent `abi/` directory contains ten matching integration ABIs. ServicePayments remains
absent: payers approve exact gross to Distributor and call payInvoice directly. Invoice has
Payment and payer only; EIP-712 domain version remains 2. Its domain and token are proxy state,
so compatible logic upgrades preserve existing signatures, authorization and replay records.

## Initial transition and preserved history

The earlier financial contracts were ordinary contracts and could not become proxies at their
existing addresses. The initial UUPS transition therefore used a fresh complete test stack.
Read-only checks immediately before deployment found no assets, organizations, orders, held
EURO or published financial rules in the old stack, and no Core service requests, service
operations or entitlements. No economic state or immutable instance was migrated or abandoned.

The preceding fourteen-component direct-invoice release is archived with its ten ABIs,
receipts, explorer and Core runtime evidence under
[chiado-10200-23685490](deployments/archive/chiado-10200-23685490/deployment.json).
The earlier fifteen-component adapter release remains in
[chiado-10200-23669346](deployments/archive/chiado-10200-23669346/deployment.json).
The [preceding release document](https://github.com/juvantia/contract/blob/905d2fb/DEPLOYMENTS.md)
retains its original evidence. Historical addresses are not current defaults.

## Authorities and payment asset

- Owner/deployer and upgrade authority: `0x3bb6869ad55fe8890de15ec8a8d8d0ac7994efd1`, encrypted Foundry account `juvantia_admin`.
- Core invoice issuer and both factory authorizers: `0x5002d9895e30a097d69dd64e98899158eb1c7610`; the existing service key is unchanged.
- Payment token: `0x7a47605930002cc2cd2c3c408d1f33fc2a18ab71`; actual on-chain decimals: `18`. No symbol was queried.
- Tribunal remains explicitly zero. Core community creation remains disabled.

Core signs invoices/vouchers off chain, while citizens authorize their own wallet operations.
Core and Tribunal have no infrastructure upgrade authority. Both Core private signing settings
retain the same existing server-only key. No private key or environment contents are published.
The temporary deployer password file was removed after successful receipt/runtime verification.

## Canonical contracts

Verified at block `23689121`, hash `0x1a8cacde0b1ef7f27539a77f33524738b8046644f7e162bb891d1020cbc4278a`.
Services and wallets use the logical role's proxy address, not its implementation address.

| Role | Address | Creation block | Creation transaction |
| --- | --- | ---: | --- |
| aerariumImplementation | `0xf6f6e1eceb35fd2d7406152021769f655bb5267e` | 23688971 | `0xc1c8223f3ab8c19d525b30b24fb84f15cd48fe9bc44e86bc54c2e05a0fc73214` |
| aerarium | `0xffd6e4f14d5100bf2a73020775c3c02e0210667b` | 23688973 | `0x8a4fc47ba32b38da8e9a023a3dfb13137df833fefac4648879b5624272211bb2` |
| revenueImplementation | `0x6bbce16862c080cb86fd6a0ba7fdf76e70a8c94e` | 23688978 | `0x2d3d582a31559cbbb1f6147b3633044a4ad6298241d1bd47fe77af1f0cee3cc8` |
| revenue | `0x99c4135e35bb7b51ed9d381b468534cd9e9909c8` | 23688998 | `0xa0f738e564950b865673b114d36818827157b520e03607e99d24f81ef9f5eb65` |
| registryImplementation | `0xe99d4261edd3a40567f55fcc526d17f4a30efa23` | 23689000 | `0x43a947671ad68a33709949be52b1eac71e645220b32b61a61ba170a0528a39ab` |
| registry | `0x867c0a7d7b1e1857def39ecd3ab6bdcd1d118079` | 23689003 | `0xe13f6a3a17ccd2d3ad644cbdb4f6b45ec6512939e71768b98fddc4f3c6df4476` |
| assetImplementation | `0xb21eb25b03e6f8d92ef87892ab4c042f96b3fdd9` | 23689027 | `0x71019c602718d1bce6b8b1d1bbf55060cccb4e0ec1c15a74c08f7063c928ae85` |
| fabricaImplementation | `0xf5ab502ef4ae24e157eaf724d0a9a266c7c9504e` | 23689046 | `0x32b5d26c99ad8b9978b1758b265915ce069e6bf608f64d63b6ed80e77d01f271` |
| fabrica | `0xffdb98d6c304c2577a0a187c8508c73873b84915` | 23689063 | `0xec6d6583ad7711bf4758c73ee00b6b710bb8e189fc257e82dc7a308710e0f581` |
| tradeImplementation | `0xe2aaa23d5ab00144dc5c85b245d5010c8f8cec35` | 23689069 | `0xa440e2ef8254b3618bce8bb0616dec1ec64e2f87de852dfc28babe69e9d7453a` |
| trade | `0xae9773b07ae24e9d3699dcdd153c21e4b1b4c1d2` | 23689071 | `0x18b658bfe68d65e82a1914a12d5d2336b2ab59afb16fee4900dd1778e2aeb0f0` |
| consortiumImplementation | `0x8d2f1f2cad07ca7dffbf24e24afca9cdb535a155` | 23689079 | `0xc05659337c10b18f77157ccd346d35ab71ce7280359922a53cf5457c44f2de9f` |
| consortiumFactoryImplementation | `0xb4b41d4bf2beeae1d9f4bda3cec139a521cb69c5` | 23689082 | `0x78c3664d757b19a2db01b440012c6970ac261bc469c1b783b49b36847aa04fc9` |
| consortiumFactory | `0xfa0e0028c9fa6a6c4f8850fe6856a32455395b61` | 23689084 | `0x520f2354288c86e7325bd8436fdd93656e4dd371ff71b4e51fd73b48fa94eb5d` |
| syndicateImplementation | `0x448fc46ae67d5d96da3e39c0e22c45b3727127c1` | 23689094 | `0x8449ee270574f65260528e96c90194d8006e3a6b1ef4698bc9576ad637abe9fe` |
| syndicateFactoryImplementation | `0xe295938bfa8c89501a939ed262ffbb7cd27cd690` | 23689097 | `0x337d7648e2ca0acb12f6bc3afc21e1362139950a71df7ea84f1cc59d746c27e8` |
| syndicateFactory | `0x8a6e815fcd5ea109ad77ccae9f294149650c50c1` | 23689105 | `0x6447dab6c879ac1e4bd6356cab8f14eca7f92e4cc1308873f03d5eaa7b6bda1e` |

## Explorer sources and names

All seventeen deployed addresses have verified public source and contract names. Verification
timestamp: `2026-10-25T19:10:29.354217+00:00` UTC. The exact original creation bytecode was reproduced
from compiler metadata before Sourcify submission. The
[explorer record](deployments/chiado-10200/explorer-verification.json) confirms all seven
ERC-1967 implementation links. Entry points are named ERC1967Proxy; implementations are
separately named by their actual Solidity contract type.

- [JuvantiaAerarium](https://gnosis-chiado.blockscout.com/address/0xffd6e4f14d5100bf2a73020775c3c02e0210667b?tab=contract)
- [JuvantiaRevenueDistributor](https://gnosis-chiado.blockscout.com/address/0x99c4135e35bb7b51ed9d381b468534cd9e9909c8?tab=contract)
- [JuvantiaPaymentRegistry](https://gnosis-chiado.blockscout.com/address/0x867c0a7d7b1e1857def39ecd3ab6bdcd1d118079?tab=contract)
- [JuvantiaAssetFabrica](https://gnosis-chiado.blockscout.com/address/0xffdb98d6c304c2577a0a187c8508c73873b84915?tab=contract)
- [JuvantiaTradeHub](https://gnosis-chiado.blockscout.com/address/0xae9773b07ae24e9d3699dcdd153c21e4b1b4c1d2?tab=contract)
- [ConsortiumFactory](https://gnosis-chiado.blockscout.com/address/0xfa0e0028c9fa6a6c4f8850fe6856a32455395b61?tab=contract)
- [SyndicateFactory](https://gnosis-chiado.blockscout.com/address/0x8a6e815fcd5ea109ad77ccae9f294149650c50c1?tab=contract)

## Core connection

Core source: [`e480cc8eeefce9e0880e3cc0bd8f095e9a4abeb1`](https://github.com/juvantia/core/commit/e480cc8eeefce9e0880e3cc0bd8f095e9a4abeb1).
Its [automatic VPS deployment](https://github.com/juvantia/core/actions/runs/40225015909) succeeded. Public
[integration evidence](deployments/chiado-10200/integration-verification.json) records matching
addresses and the same service key, matching compiled runtime files, successful application
startup, zero restarts, no adapter setting and no private .env inside the image. Server private
configuration has mode 600. GitHub ENV_CORE is the persistent deployment source; unrelated
settings were preserved. Public trade reading returned 200/zero orders; unauthenticated profile
reading returned 401. These do not establish paid lifecycle acceptance.

| Core setting | Canonical proxy role |
| --- | --- |
| PAYMENT_REGISTRY_ADDRESS | registry |
| REVENUE_DISTRIBUTOR_ADDRESS | revenue |
| TRADE_HUB_ADDRESS | trade |
| AERARIUM_ADDRESS | aerarium |
| CONSORTIUM_FACTORY_ADDRESS | consortiumFactory |
| SYNDICATE_FACTORY_ADDRESS | syndicateFactory |

There is no SERVICE_PAYMENTS_ADDRESS. The same invoice issuer/authorizer identity is retained;
COMMUNITY_CREATION_ENABLED=false keeps deferred consents, voucher fields and canonical creation
receipt/caller proof outside activation. ZeroDev connectivity and sponsorship were not retested,
as requested by the owner. No database economic rows were rewritten.

The native payment ABI and public API envelope are unchanged by UUPS. Existing direct-invoice
app commit [79a2092](https://github.com/juvantia/app/commit/79a2092) and its
[successful CI](https://github.com/juvantia/app/actions/runs/40175501816) remain applicable.
It had 307 passing tests and both native JavaScript exports. This infrastructure change adds
no native binary or OTA publication.

## Verification and future upgrades

- 186 Foundry tests pass, including nine new populated-state upgrade cases and the earlier
  financial, escrow, signature, replay and governance regressions (512 fuzz runs).
- Three Python regressions verify the storage checker rejects removal, reordering, offset/
  type/nested-struct and pinned-dependency changes. Its separately named V2 candidates pass.
- The reviewed storage baseline is storage-layout/infrastructure-v1.json. PaymentSettlement's
  base layout is frozen; append new Distributor state at the end of the concrete contract.
- Atomic proxy initialization and locked implementation initializers are checked. RPC verifies
  all seven implementation slots, proxiable UUIDs, implementation owners/initializer locks and
  initialized proxy versions, along with actual financial dependencies and roles.
- Solidity 0.8.30, Cancun, optimizer 200; formatting and build size checks pass. Distributor
  runtime is 23,607 bytes (969-byte EIP-170 margin); Aerarium 6,008; Registry 6,506. Test V2 is
  23,906; fixed Syndicate remains 24,357. Preserve the size gate for future changes.
- Core's 200 tests, typecheck/build pass. All sixty used ABI entries match the new exports.
  A read-only check verifies Core/Solidity EIP-712 digest/domain version 2 and issuer grant.
  Its deliberately invalid diagnostic invoice cannot settle; no payment was broadcast.

Reproduce receipt and explorer verification with the matching build and raw local broadcast:

```sh
python3 script/verify_deployment.py broadcast/DeployJuvantia.s.sol/10200/run-latest.json deployments/chiado-10200
python3 script/verify_explorer.py deployments/chiado-10200/deployment.json broadcast/DeployJuvantia.s.sol/10200/run-latest.json https://gnosis-chiado.blockscout.com --method sourcify
python3 script/check_storage_layout.py
```

Both verifiers use no wallet or transaction. The receipt exporter archives earlier ABI/address/
source/runtime evidence before replacement. Raw broadcasts stay local. deploy.sh simulates by
default; broadcasts require explicit authorization and an encrypted account. Blind resume or
skipping simulation is rejected. GitHub Actions checks source/storage/tests only and does not
deploy contracts. See [UPGRADES.md](UPGRADES.md) for owner-authorized upgrade procedure.

Financial categories and real paid invoice/entitlement, rental/Cloud Menu, trade, budget and
claimAll acceptance remain separate activation work. Registry owners select/publish actual
categories and BPS; Admin drafts activate nothing. No tariffs, category names or zero-tax rules
were invented and no EURO payment or entitlement was fabricated for deployment verification.
Remaining Admin and physical-device acceptance and deferred organization workflow proof remain
separate. See [Core readiness](../core/docs/DEPLOYMENT_READINESS.md).
