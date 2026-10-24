# Juvantia Smart Contract Deployments

## Verified Chiado deployment — 2026-10-24

The full contract stack is deployed on Gnosis Chiado (chain ID 10200), from source revision
`a061464`. All 29 deployment/configuration transactions have successful RPC-verified receipts,
in blocks 23669318–23669346. All 15 deployed runtimes match the compiled artifacts (immutable
slots excluded from byte comparison and dependencies checked through getters). The verification
also checks 46 values: ownership, shared Core identity, token decimals, contract dependencies,
source/registrar/escrow roles and all four ERC-1967 implementation slots.

The canonical [deployment registry](deployments/chiado-10200/deployment.json) includes every
address, creation transaction, deployment block, receipt block hash and runtime SHA-256.
The adjacent `abi/` directory exports all 11 integration ABIs from the verified build.
Reproduce verification with:

```sh
python3 script/verify_deployment.py broadcast/DeployJuvantia.s.sol/10200/run-latest.json deployments/chiado-10200
```

The restored encrypted `juvantia_admin` is the initial owner. One Core service key is
configured identically in both signing settings, stored in ignored local/server environment
files (mode 600) and GitHub Secret `ENV_CORE`. Its public identity is authorized in Registry
and both factories. No private key or environment contents are recorded in this document or
committed to Git. The temporary deployer password file was removed after broadcasting.
Core was subsequently connected and deployed as recorded below.

The owner explicitly deferred Tribunal: its address is zero in Distributor, Fabrica and both
community factories. Judicial operations remain disabled. The agreed escrow, voting, protected
rank, spending and quote-boundary source corrections pass all 172 tests, formatting and build
size checks. Real-network Forge simulation and sequential broadcast both completed successfully.
An independent fork acceptance run is not required by the owner.

The full deployment now requires explicit `DEPLOYER_ADDRESS`, token decimals and all Core/
Tribunal settings in [.env.example](.env.example). The expected deployer is the initial owner;
owner and Core must be distinct nonzero authorities. Tribunal may explicitly be zero; a
future nonzero Tribunal must differ from both. Owner-only setters can activate it later.
Existing asset/community clones require their own Tribunal setting; factory changes affect
future clones. Token decimals are read from the actual token, without its symbol, and
checked against configuration.
Supported token decimals are 0-72. `deploy.sh` simulates by default; actual broadcasting uses
an explicit `--broadcast` after authorization. Simulation uses only the public sender;
the encrypted account is selected for an explicit broadcast. The entry point rejects
`--skip-simulation` and `--resume`; inspect actual receipts before any partial-deployment recovery.

Consortium creation vouchers now sign the owners' initial `pettyLimit`/`majorLimit` base-unit
package. Core's deferred organization-creation path needs that matching voucher ABI before
enablement. The new factory/asset/community source is for fresh instances, not an automatic
upgrade or migration of historical clones. All canonical address/block/receipt entries below are backed by successful RPC receipts.

## Core connection — verified 2026-10-24

The existing VPS service `core-service` is connected to the canonical Chiado stack.
Core source revision: [`2539af45e8fbf46ba64aa1d0e1a4a7e221c93506`](https://github.com/juvantia/core/commit/2539af45e8fbf46ba64aa1d0e1a4a7e221c93506).
The [Build & Auto-Deploy workflow](https://github.com/juvantia/core/actions/runs/40093914067)
completed successfully. Post-deployment verification confirmed the deployed source revision,
a running container with zero restarts, successful application startup and the configuration
and service signer matching the deployment registry.

Core's local/server environment and GitHub `ENV_CORE` contain the selected chain/RPC/token,
18 token decimals, both public signing roles and the following canonical contract bindings.
Use factory/TradeHub proxies, rather than their implementation addresses.

| Core setting | Role in `deployment.json` |
| --- | --- |
| `PAYMENT_REGISTRY_ADDRESS` | `registry` |
| `REVENUE_DISTRIBUTOR_ADDRESS` | `revenue` |
| `SERVICE_PAYMENTS_ADDRESS` | `services` |
| `TRADE_HUB_ADDRESS` | `trade` |
| `AERARIUM_ADDRESS` | `aerarium` |
| `CONSORTIUM_FACTORY_ADDRESS` | `consortiumFactory` |
| `SYNDICATE_FACTORY_ADDRESS` | `syndicateFactory` |

`PAYMENT_INVOICE_SIGNING_KEY` and `COMMUNITY_AUTHORIZER_PRIVATE_KEY` contain the same
service key. Both configured public roles match its derived address. Core now rejects missing
release settings, zero/malformed addresses, invalid or differing keys and mismatched public
roles. Implicit chain/token defaults, contract placeholders and the fallback test signing key
were removed. Environment files are excluded from Docker build context; runtime configuration
is loaded through Compose `env_file`. Future deployments restore it from `ENV_CORE`.

Local validation passed: 195 Core tests, TypeScript typecheck and build. All 62 checked Core
function/event ABI entries match the verified deployment exports; the unused, nonexistent
`distributeRevenue(address,uint256)` ABI entry was removed. Runtime verification confirmed:

- Public TradeHub order reading returned HTTP 200 and zero orders at verification time.
- A profile request without a verified session returned HTTP 401.
- Runtime contract addresses and the derived Core signer matched the canonical release.
- Both persisted signing settings matched the provisioned key; server `.env` had mode 600.
- The private `.env` file was absent from the runtime image.
- Wallet table chain constraints already selected 10200; no chain-constraint migration was needed.

`COMMUNITY_CREATION_ENABLED=false` keeps creation fees, voucher signing and submitted
community deployment confirmation disabled. Participant consent/caller authorization,
canonical creation receipts and the current Consortium voucher's `pettyLimit`/`majorLimit`
fields must be completed before enabling that workflow. Tribunal remains disabled separately.
ZeroDev connectivity and gas sponsorship were not retested at the owner's request.

Financial category/rate publication and real paid lifecycle acceptance remain pending.
These deployment and read/authentication checks do not establish successful payment settlement,
service entitlements, revenue collection, Admin/client activation or a native release.

## Historical preparation — 2026-10-06

At this historical preparation stage, the network had not yet been selected and no canonical
universal-settlement deployment had been receipt-verified. Those source/documentation changes
broadcast no transactions. The later Chiado deployment and Core connection are recorded above.

The clarified tax-only, seller-priced model is documented in
[Core PAYMENTS.md](../core/docs/PAYMENTS.md). Additional commissions are removed from source,
ABIs, reviews and public DTOs. Registry prices and compiled category identifiers are removed. Seller service/order data
supplies both independently. General beneficiary association remains separate integration work;
organization creation and organizational payer identity are deferred to a later phase. These differences are described in
[PAYMENT_IMPLEMENTATION.md](../core/docs/PAYMENT_IMPLEMENTATION.md); they are not fixed by this update.
Activation requires release configuration and receipt-verified deployment. Deferred organization
workflows require their own proof/authorization completion before enablement.
Core's device service recipient switching uses authoritative published renter_id (MVP physical
persons); scheduled publication, recovery and recipient snapshots are implemented in Core.
Live acceptance against the chosen chain remains after receipt-verified deployment. All agreement payments always
earn owners independently of current renter/operator or payment time. See [leasing requirements](../core/docs/LEASING.md)
and [implementation TODO](../core/docs/PAYMENT_TODO.md); documentation does not activate routing.

Contract settlement source, tests and the full-stack deployment script are implemented.
Core invoice signing and receipt-based payment integration are implemented; complete Core
readiness remains subject to the documented gaps and live acceptance.

See [PAYMENT_PROTOCOL.md](PAYMENT_PROTOCOL.md), [Core signing](../core/docs/SIGNING.md)
and [Core readiness](../core/docs/DEPLOYMENT_READINESS.md).

## Release configuration

Deployment configuration is supplied at release time through:

- `BLOCKCHAIN_CHAIN_ID`
- `BLOCKCHAIN_RPC_URL`
- `DEPLOYER_ADDRESS`: expected deployment signer and initial owner
- `DEPLOYER_ACCOUNT`: encrypted Foundry account label for broadcasting
- `EURO_TOKEN_ADDRESS`
- `EURO_TOKEN_DECIMALS` in the services, checked against the actual token
- `PAYMENT_INVOICE_ISSUER_ADDRESS`: public address derived from the single Core service key
- `COMMUNITY_AUTHORIZER_ADDRESS`: the same Core public address, used by both community factories
- `TRIBUNAL_ADDRESS`: explicit zero while deferred, otherwise the selected distinct authority

Core receives one server-only private key: the same 0x-prefixed secret is supplied to both
PAYMENT_INVOICE_SIGNING_KEY and COMMUNITY_AUTHORIZER_PRIVATE_KEY. These are existing consumer
settings, not two key pairs. Its one derived public address must be available before deployment
and supplied to both public address settings above. Private keys and production configuration
must not be recorded here. This Core key signs invoices and creation vouchers off chain and
needs no token/native balance. Users authorize their own operations; owner/deployer transactions
have a separate gas payer. DeployJuvantia.s.sol grants the same Core address in Registry and
installs it as the authorizer of both factories. See [Core signing](../core/docs/SIGNING.md).

## Complete deployment inventory

Deploy script: script/DeployJuvantia.s.sol. Prepare and verify the complete set:

- JuvantiaPaymentRegistry, JuvantiaAerarium and JuvantiaRevenueDistributor.
- JuvantiaServicePayments, bound to Distributor.
- JuvantiaAsset implementation and JuvantiaAssetFabrica implementation/proxy.
- JuvantiaTradeHub implementation/proxy.
- Consortium implementation and ConsortiumFactory implementation/proxy.
- Syndicate implementation and SyndicateFactory implementation/proxy.
- Tribunal is explicitly disabled for this release. The script does not deploy a Tribunal
  constitution/jury system. Its authority can be assigned later through owner/admin setters.

Verify Fabrica and Consortium factory asset registrars; Syndicate factory payment registrar;
TradeHub escrow/source; ServicePayments/Aerarium sources; Consortium/Syndicate instance roles.
Source bits are TradeHub=1, ServicePayments=2, Consortium=4, Syndicate=8 and Aerarium=16.

## Activation evidence and remaining work

Completed for this release:

1. Receipt verification of all deployment/configuration transactions, token/decimals,
   proxy implementations and cross-contract bindings.
2. Export of canonical addresses, blocks, receipts and all 11 integration ABIs.
3. Core configuration/key provisioning, ABI checks, automated deployment and runtime
   contract-read/authentication checks described above. The same service identity is authorized
   in Registry and both factories; owner and Tribunal authority remain separate.

Remaining before claiming paid lifecycle acceptance:

1. Publish the administrator's selected tax categories/BPS with the actual Registry owner.
   Saving a draft activates nothing. Seller tariffs belong to seller service configuration,
   not the tax catalog. Include the separately taxed owners' allocation operation and the
   domain-required private zero-charge principal rules. No category catalog or prices are
   prescribed by this deployment record.
2. Exercise actual paid invoice/entitlement, trade, operating/budget spending, public custom
   settlement and claimAll receipts. Verify gross = tax + net, the real payer and beneficiary,
   unchanged historical invoices, replay/expiry failures and ambiguous-send recovery. Include
   device service routing with/without published renter_id, rental minute boundaries,
   WS revocation/reconnect and Cloud Menu editor handover. Agreement payments must credit
   owners before/during/after rental and after operator/renter changes.
3. Complete the deferred community consent, caller authorization and creation receipt checks,
   update the Consortium voucher fields and then validate civic fee/factory creation and owners'
   allocation before enabling community creation. Organizational payer support and other
   remaining integration gaps are tracked in [Core readiness](../core/docs/DEPLOYMENT_READINESS.md).
4. Configure and verify remaining Admin/client integrations against this canonical stack.
   Native binary/OTA publication requires its own release authorization.

Key rotation must update both Core secret settings, both public roles, the Registry issuer
grant and both factory authorizers. Reverify the same new identity across those verification
points before resuming signature issuance.

Net is a central credit until collection; tax reaches Aerarium immediately.
Rule tuple and Settlement event signatures changed. Export matching ABIs for all services and
use a fresh configured-stack deployment; the non-upgradeable Registry is not upgraded in place.
Consortium allocation has its own tax; collecting existing credits has no new levy.
TradeHub.pendingWithdrawals is a compatibility read, and TradeHub has no euro withdraw route.

## Canonical receipt record — Chiado 10200

Verified at block `23669346`, hash `0x45001b9f12817085ec8e1f888d20ad927b295f881e1b68b0e640e7aadacd8ded`.
Payment token: `0x7a47605930002cc2cd2c3c408d1f33fc2a18ab71`, decimals `18`.
Core public signer: `0x5002d9895e30a097d69dd64e98899158eb1c7610`. Tribunal: explicitly disabled (zero).

| Role | Address | Creation block | Creation transaction |
| --- | --- | ---: | --- |
| aerarium | `0x8f0fce54c6e16de7a624434924cb02c9a1ca548f` | 23669318 | `0xfae54633aa326b3b19d0cc31a86dfcf1f1166c80a1d29f56e488afa2336f2cca` |
| revenue | `0x348cbd92ba4fbe9b620a64dc9206a56bc5239dfc` | 23669319 | `0xd5ed5dbd77adfa31ff24e46fb4c156c79a638ea6ec8ee99d91c479abc3005648` |
| registry | `0xfbda454aea593ff61f28158f1a088e7a363bdf3c` | 23669320 | `0x7b789ac734d976bb662372e2564169a335f2f9485e866355213dc25dc5bb8b3f` |
| assetImplementation | `0x44e69de7d68514533a5a57acf3f61e03b21fb5b3` | 23669325 | `0x3d18861084d74f051a74cc8dd5a33c2d39d729a9a1be5330cba994a1f3fc9583` |
| fabricaImplementation | `0x5d73a2668265d60d01bfe8454d091ed0b8f8c12a` | 23669326 | `0xa7c02d3caff7f27008819f79c1ed3f7fe80f21e0839ab557092810b71a01d7a9` |
| fabrica | `0x6eeeb06caf77900b8122cf4521e7e68d0ac00057` | 23669327 | `0x31530284caaf7b6567e0e30e800515a718070071640274690f76d223a4f7e3e6` |
| tradeImplementation | `0x367c75ed357457b2881f85cb0ee2bccfe3fcb929` | 23669329 | `0x8cbb945bf7ee96dddc387ae97a5facf1817939118831db80896676f36f8931eb` |
| trade | `0x8271615888d1d3e6868487a5ac276cb3179bed97` | 23669330 | `0x2d64155e56cc538b7731ca3201af59b47d83ab1ed2d07d7932b9f8a47da6ca51` |
| services | `0xdbb173e9665fe776ed9f870607d2e39b0a1e9469` | 23669333 | `0x72de659007032a5c18e79af46d0167e98b907c9115f3f7d7004b7c7dccf46d4e` |
| consortiumImplementation | `0xfc652ccfd32b59c71e5092b9966f8235e99af76c` | 23669335 | `0x27b3c8fa39e68c10565189d43a0bc692aede72460af4e222aef5d648e5143ec0` |
| consortiumFactoryImplementation | `0x7e68fdda1cfb6b610986c22ca26c11b414b16f6c` | 23669336 | `0x9ee7c3b088be2b32c46c3c5b9c2e6834cabe9855a083c11deb65ec7dbda9816c` |
| consortiumFactory | `0xa497f79ef7a5bcb87dc5799a12c8f01a92489b23` | 23669337 | `0x1f8b605a9908d9dcc2ced70f7bf2a382c7ba2c32520f0dcb90bc9ba1d3470526` |
| syndicateImplementation | `0xa1c87b65c004de1463a8c2d8aed0b37ab1d56803` | 23669340 | `0xa40f3755e1c4d6d46ac2156f05d7dab33cc5e030e7d32428db278698af34eedb` |
| syndicateFactoryImplementation | `0xc89c3969fc73d0f5d090a97f790226e6707f69fa` | 23669341 | `0x201cf558aacf8476fa5ce0e345ca9a3db7701419f61392fc44d11baeb4465e17` |
| syndicateFactory | `0xe1df824c17babcc05cdd8a423cd8c589edb087f1` | 23669342 | `0x7070c3f6a333ddefe22202cc84fb7c4b47ba1d4145b8915dc02f9383a3f50270` |

All creation and configuration receipts and proxy relationships are also recorded in the
[machine-readable registry](deployments/chiado-10200/deployment.json). No old clones, balances
or economic state migrate automatically. Core connection is verified above. Tax-category
publication, real paid lifecycle acceptance and remaining Admin/client integrations are pending.
Native binary/OTA publication has not occurred.

## Seller category and price release update — 2026-10-07

Rule now contains active/publicAccess/destinations/taxBps/sourceRoles only; there is no servicePrice.
No financial category names or selling prices are built into runtime contracts.
createOrder(asset,amount,pricePerShare,categoryId) snapshots seller category plus price/revision;
TradeHub appends orderCategory after existing state, preserving all prior UUPS slots.
Distributor.distributeRevenue(asset,gross,categoryId), budget spend/spendReviewed, operating and
judicial payments require a supplied category. Financial Consortium proposals bind categoryId;
Syndicate collection rounds bind collection/refund categories. Authorities and full-principal
checks remain unchanged. Organization backend workflow completion is deferred, not established
by these interface changes. Export matching ABIs before chain activation; old argument lists
are not silently accepted with a default category. That source update sent no on-chain
transaction; the later Chiado deployment is recorded above.
