# Contract Instructions (`contract`)

**Service**: `contract` (Onchain Smart Contracts Layer)  
**Target blockchain**: configured by `BLOCKCHAIN_CHAIN_ID` and `BLOCKCHAIN_RPC_URL`
**Core Toolchain**: Foundry (Forge), OpenZeppelin Contracts Upgradeable (UUPS & EIP-1167 Clones).

---

## 🏛️ Description & System Role
The `contract` repository contains the smart contracts governing Real-World Asset (RWA) tokenization, fractional share trading, and revenue distribution across the Juvantia ecosystem.

The configurable ZeroDev migration is in progress, not deployed. The user is still selecting the
network; do not assume historic Arc/Chiado profiles are the selected deployment target.
The payment asset is configured through EURO_TOKEN_ADDRESS and EURO_TOKEN_DECIMALS; verify
actual token decimals on chain. Do not query/store its symbol. All money uses integer base units.
Old economic state and addresses are not migration targets. See [DEPLOYMENTS.md](DEPLOYMENTS.md)
and [Core activation readiness](../core/docs/DEPLOYMENT_READINESS.md).

---

## ⚙️ Core Architecture & Design Patterns

### 1. Minimal Proxy Pattern (EIP-1167)
To optimize gas efficiency when minting new RWA assets (Robulus, Domus, Cella, Apparatus, Sector), `JuvantiaAssetFabrica` deploys lightweight `JuvantiaAsset` minimal proxies using OpenZeppelin's `Clones` library.

### 2. Factory Upgradeability (UUPS - ERC-1967)
`JuvantiaAssetFabrica` and `JuvantiaTradeHub` are deployed behind ERC-1967 Proxies inheriting from OpenZeppelin `UUPSUpgradeable` and `OwnableUpgradeable`. Upgrades are authorized via `_authorizeUpgrade`.

### 3. Clone and Proxy Initialization & Sub-Asset Hierarchy
Clone/proxy instance state is initialized atomically through guarded `initialize()` functions. Implementation constructors disable initializers and may set checked immutable dependencies; they must not be mistaken for instance initialization. Plain non-proxy contracts use checked constructor configuration. Deployer remains the factory/upgrade authority on the configured blockchain.

`JuvantiaAssetFabrica` supports hierarchical sub-asset linking (`parentAsset` and `subAssets`). Sub-assets such as `Cella` (individual apartment/unit inside a multi-unit `Domus`) are deployed via `createSubAsset(parentAssetId, assetId, name, symbol, initialOwner)`. The parent `Domus` retains 100,000 APU for building-level rights (commercial facade advertising, rooftop antennas, common spaces), while each `Cella` receives 100,000 APU for private residential leasing and ownership. Token identifiers enforce the canonical hierarchy: `DM-XXXX` for the Domus and `DM-XXXX-C{N}` for each constituent Cella.

---

## 📜 Smart Contract Inventory

| Smart Contract | Architecture | Role & Responsibility |
| :--- | :--- | :--- |
| **`JuvantiaAssetFabrica.sol`** | UUPS Upgradeable Proxy | Asset Factory entry point. Deploys and registers new `JuvantiaAsset` tokens, managing parent-child asset hierarchy (`parentAsset`, `subAssets`, `createSubAsset`). |
| **`JuvantiaAsset.sol`** | EIP-1167 Cloneable ERC-20 | Standard RWA asset token contract (18 decimal places, 100,000 total supply per asset). |
| **`JuvantiaTradeHub.sol`** | UUPS Upgradeable Proxy | Registered-share escrow; euro price per full share, integer ceiling for fills; forwards seller proceeds atomically to RevenueDistributor and has no withdrawal method. Unsold shares retain their seller's revenue rights. |
| **`JuvantiaRevenueDistributor.sol`** | Onchain accrual vault | Transfer-aware per-asset revenue with fractional remainders, attributed marketplace custody, seller-specific trade proceeds, unified claims, atomic tax/net revenue routing (`processPayment`), and Multi-Model Tribunal encumbrance / judicial revenue seizure (`setEncumbrance`, `judicialClaim`). |
| **`JuvantiaAerarium.sol`** | Central budget | Immediate tax custody, registry-delegated tax reads, and owner-authorized spending through Distributor. |
| **`JuvantiaPaymentRegistry.sol`** | Non-upgradeable rule registry | Owner-published category revisions, taxes, permitted destinations/sources, invoice issuer grants; no seller prices. |
| **`JuvantiaServicePayments.sol`** | Receipt-oriented payment gateway | Exact request/payer/recipient/amount events for backend entitlement verification. |
| **`community/ConsortiumTreasury.sol`** | Abstract clone-compatible foundation | Operating custody and governed allocation of owners' revenue earnings into RevenueDistributor; read-only views of its distributed reserve. |
| **`community/Consortium.sol` / `Syndicate.sol`** | Cloneable organizations | Authorized operating settlement, Consortium owners' allocation, Syndicate quotas/refunds, governance and Tribunal enforcement. |
| **`community/ConsortiumFactory.sol` / `SyndicateFactory.sol`** | UUPS factories / EIP-1167 clones | Community creation voucher authorization, instance initialization, asset/source registration and receipt events. |

Consortium governance/Tribunal gate, Syndicate governance/points and both factories remain required. `ConsortiumTreasuryHarness` is test-only and must never be deployed as a production governance substitute.

### 4. Universal Settlement

Business requirements: [Core PAYMENTS.md](../core/docs/PAYMENTS.md).
The seller sets price, category and one beneficiary. Categories select tax BPS only.
Core confirms amount/payer; Custodia reviews economic classification after payment.
There is no additional commission deduction. A Civitas service named a commission remains
a seller-priced service. Shared sale income goes to a Consortium, followed by separate allocation.
An organization's beneficiary is its factory-created contract address. A representative does
not assign or replace that address; owners elect spending authority on chain.
Every payment under a Core rental agreement earns its registered owners' pool regardless of
current renter/operator or payment time. For device services Core uses authoritative published
renter_id: verified physical-person account if present, owners' pool otherwise. Leasing maintains
that field at minute boundaries; the service selector does not recheck lease payments/dates.
Core signs the recipient snapshot; Distributor does not read Core's rental state.
Core's recipient switching, agreement snapshots and scoped workshop/Link access are implemented.
Actual monetary acceptance still requires the selected chain and receipt-verified activation. See [leasing requirements](../core/docs/LEASING.md)
and [implementation TODO](../core/docs/PAYMENT_TODO.md).
Seller service/order data now supplies prices and categories; no names or prices are compiled into settlement.
see [implementation differences](../core/docs/PAYMENT_IMPLEMENTATION.md). The source behavior
below is a technical reference, not an expansion of the clarified business requirements.

All official non-P2P payments enter RevenueDistributor first. PaymentRegistry is non-upgradeable;
only its owner publishes versioned rules. Tax immediately enters Aerarium; addressed net
accrues centrally. Asset net retains the transfer-aware O(1) index, fractional remainders,
attributed escrow and Consortium treasury exclusion. Consortium allocation has its own tax category;
governance approves gross and the owners' pool contains net. ServicePayments validates signed invoices
as a receipt adapter and holds no funds. TradeHub buyers approve/pay Distributor directly. Claims
include account receipts, pooled owner earnings and trade proceeds through claimAll.

See [PAYMENT_PROTOCOL.md](PAYMENT_PROTOCOL.md) for current interfaces and historical revisions.
Refund policy is outside this phase; existing principal mechanisms remain domain-specific.
No automatic historical balance migration.

### Current implementation and integration boundaries

- Gross includes tax: tax=floor(gross*taxBps/10000), net=gross-tax. Additional commission
  configuration, deduction and recipient crediting are removed. Registry-linked service prices
  remain a separate implementation difference.
- Registry is financial truth; saving Admin drafts publishes no rules. Unknown/inactive
  categories fail closed, and zero-tax rules must be explicitly published.
- Tax enters Aerarium immediately; addressed net accrue inside Distributor.
  Asset-pool net uses transfer-aware accrual; trade proceeds belong to the particular seller.
  Collection of already-accrued funds adds no new levy.
- Consortium allocation is a distinct taxable operation under the category bound in its governance proposal.
  Governance approves gross and eligible owners accrue net. The second account is in
  Distributor, outside operating custody. Treasury shares, including attributed escrow,
  earn nothing from that pool. There is no local Consortium owner payout/index.
- Use **owners' revenue earnings** in documents, identifiers and product copy.
- Public custom contracts settle their own funds through pay(categoryId, paymentId, gross,
  kind, destination), without individual source registration or a Core signature.
  They need a published public category, unique ID and the configured token/decimals.
  Account recipients need no registration; custom owner pools require compatible registered assets.
- Only configured sources can use delegated payer debits/private categories. Every such source
  must authenticate its real payer. Source roles: TradeHub=1, ServicePayments=2,
  Consortium=4, Syndicate=8, Aerarium=16.
- One payment has one principal net recipient/pool and budget tax. No additional deduction
  recipient or arbitrary sale split is supported.
- Existing refundable Syndicate quotas/refunds and judicial principal routes require private
  published zero-charge rules. A new commercial refund policy is not implemented.
- Arbitrary external ERC-20 transfers cannot be globally blocked. Financial routing alone
  does not establish official-service status, hardware entitlement or other obligations.
- TradeHub.pendingWithdrawals is a compatibility read of Distributor sale proceeds.
  TradeHub has no withdraw method; its old private mapping remains a reserved UUPS slot.

### Core service signatures

Core uses one service key for off-chain invoices and community creation vouchers. Invoice issuer
and factory authorizer are verification roles of the same Core identity. The user signs the
actual wallet operation; Distributor verifies issuer authorization on chain. The issuer does
not submit citizen transactions and is not the owner or Tribunal. Public pay and earnings
claims require no Core signature. The older backend-signed claim model is superseded.

PAYMENT_INVOICE_SIGNING_KEY and COMMUNITY_AUTHORIZER_PRIVATE_KEY contain the same server-only
secret. PAYMENT_INVOICE_ISSUER_ADDRESS and COMMUNITY_AUTHORIZER_ADDRESS contain its same derived
public address. DeployJuvantia.s.sol grants that address in Registry and configures it in both
factories. The key signs factory vouchers after required draft checks/consents and belongs only
in Core secret configuration, never source, logs, public config or responses. Off-chain signing
consumes no gas and needs no funded signer balance. Rotation updates Registry and both factories.
See [Core signing roles](../core/docs/SIGNING.md).

### 5. Multi-Model Tribunal & Judicial Encumbrance Architecture

To enforce legal decisions, court verdicts, and restitution onchain without compromising financial precision, Juvantia contracts integrate judicial authority (`tribunal`):
- **Asset Seizure (`JuvantiaAsset.sol`):** `judicialTransfer` and `judicialSeize` allow the Tribunal to forcibly reassign APU share tokens from a defendant to a claimant or treasury.
- **Corporate Seizure (`Consortium.sol` / `Syndicate.sol`):** `judicialSeizePayment` and `judicialSeizeToken` permit direct confiscation of operating EURO or held asset tokens by judicial decree.
- **Revenue Distributor Encumbrance & Seizure (`JuvantiaRevenueDistributor.sol`):**
  - **Account Encumbrance (`setEncumbrance`):** The Tribunal can place an encumbrance/freeze on any account address (`encumbered[account] = true`). Encumbered accounts are strictly barred from claiming accrued revenue (`claim`, `claimFor`).
  - **Judicial Revenue Seizure (`judicialClaim` / `judicialSeize`):** The Tribunal can seize an account's accrued EURO revenue (full balance or a specified fine/award amount) and redirect it immediately to a victim or court deposit.
  - **Accounting Precision:** Revenue checkpoints remain active during encumbrance, preserving mathematical precision and fair yield accrual while locking fund withdrawals until judicial release.

---

## 📍 Deployment Status

No new configurable deployment has been performed. Full deployment requires all community contracts/factories, role wiring, ABI/address/deployment-block registry export and receipt-verified smoke tests. Never invent addresses or mark successful compilation as deployment.

Settlement source/tests are implemented; this does not establish complete Core readiness.
Core still has incomplete consent verification, community deployment receipt/caller checks,
historic/dummy configuration fallbacks and chain-cutover schema constraints. These are documented
gaps, not fixed by this documentation update; see [readiness](../core/docs/DEPLOYMENT_READINESS.md).
Native binary/OTA publication is separate from server/contract activation.

---

## 🛠️ Developer Workflow Commands (Foundry)

- **Compile**: `forge build`
- **Run Unit Tests**: `forge test`
- **Configuration**: Solidity 0.8.30, Cancun, optimizer 200, 512 fuzz runs.
- **Deployment gate**: `DeployJuvantia.s.sol` requires explicit blockchain and euro-token environment variables, but prepares full community/source wiring; receipt-verified canonical registry export remains required. Do not broadcast a partial migration as the completed stack.
- **Confirmation**: Backend verifies the specific successful UserOperation and transaction receipt; no consensus-finality wait, webhook or permanent indexer.

---

## ⚠️ Storage Layout & Upgrade Mandates
When modifying upgradeable contracts (`JuvantiaAssetFabrica`, `JuvantiaTradeHub`):
- **Never modify existing storage variable order**. Always append new state variables to the bottom of the contract storage layout to prevent storage collisions during upgrades.
- **Always update the canonical deployment registry and [`DEPLOYMENTS.md`](DEPLOYMENTS.md)** immediately after receipt-verified deployments or upgrades.
- Release preparation/status may be documented before deployment, but addresses, transactions,
  deployment blocks and "live" claims must appear only with verified receipt evidence.
