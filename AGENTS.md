# Contract Instructions (`contract`)

**Service**: `contract` (Onchain Smart Contracts Layer)  
**Target blockchain**: configured by `BLOCKCHAIN_CHAIN_ID` and `BLOCKCHAIN_RPC_URL`
**Core Toolchain**: Foundry (Forge), OpenZeppelin Contracts Upgradeable (UUPS & EIP-1167 Clones).

---

## 🏛️ Description & System Role
The `contract` repository contains the smart contracts governing Real-World Asset (RWA) tokenization, fractional share trading, and revenue distribution across the Juvantia ecosystem.

The configurable ZeroDev migration is in progress, not deployed. The payment asset is the euro token configured locally through `EURO_TOKEN_ADDRESS` and `EURO_TOKEN_DECIMALS`; payment integrations verify the actual token decimals on chain against configuration. Do not query or store its symbol. All money uses integer base units. Old economic state and addresses are not migration targets. See [full migration progress](../ZERODEV_MIGRATION_PROGRESS.md).

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
| **`JuvantiaServicePayments.sol`** | Receipt-oriented payment gateway | Exact request/payer/recipient/amount events for backend entitlement verification. |
| **`community/ConsortiumTreasury.sol`** | Abstract clone-compatible foundation | Operating custody and governed allocation of owners' revenue earnings into RevenueDistributor; read-only views of its distributed reserve. |

Consortium governance/Tribunal gate, Syndicate governance/points and both factories remain required. `ConsortiumTreasuryHarness` is test-only and must never be deployed as a production governance substitute.

### 4. Universal Settlement

All official non-P2P payments enter RevenueDistributor first. PaymentRegistry is non-upgradeable;
only its owner publishes versioned rules. Tax immediately enters Aerarium; addressed net and
commission accrue centrally. Asset net retains the transfer-aware O(1) index, fractional remainders,
attributed escrow and Consortium treasury exclusion. Consortium allocation has its own tax category;
governance approves gross and the owners' pool contains net. ServicePayments validates signed invoices
as a receipt adapter and holds no funds. TradeHub buyers approve/pay Distributor directly. Claims
include account receipts, pooled owner earnings and trade proceeds through claimAll.

See [PAYMENT_PROTOCOL.md](PAYMENT_PROTOCOL.md) for sources, historical invoice/proposal rules,
principal refunds, evidence and release preparation. No automatic historical balance migration.

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
