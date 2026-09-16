# Contract Manifest (`contract`)

**Service**: `contract` (Onchain Smart Contracts Layer)  
**Target blockchain**: configured by `BLOCKCHAIN_CHAIN_ID` and `BLOCKCHAIN_RPC_URL`
**Core Toolchain**: Foundry (Forge), OpenZeppelin Contracts Upgradeable (UUPS & EIP-1167 Clones).

---

## 🏛️ Description & System Role
The `contract` repository contains the smart contracts governing Real-World Asset (RWA) tokenization, fractional share trading, and revenue distribution across the Juvantia ecosystem.

The configurable ZeroDev migration is in progress, not deployed. The payment asset is the euro token at `EURO_TOKEN_ADDRESS`; its decimals come from the token contract. Do not query or store its symbol. All money uses integer base units. Old economic state and addresses are not migration targets. See [full migration progress](../ZERODEV_MIGRATION_PROGRESS.md).

---

## ⚙️ Core Architecture & Design Patterns

### 1. Minimal Proxy Pattern (EIP-1167)
To optimize gas efficiency when minting new RWA assets (Robulus, Domus, Apparatus, Sector), `JuvantiaAssetFabrica` deploys lightweight `JuvantiaAsset` minimal proxies using OpenZeppelin's `Clones` library.

### 2. Factory Upgradeability (UUPS - ERC-1967)
`JuvantiaAssetFabrica` and `JuvantiaTradeHub` are deployed behind ERC-1967 Proxies inheriting from OpenZeppelin `UUPSUpgradeable` and `OwnableUpgradeable`. Upgrades are authorized via `_authorizeUpgrade`.

### 3. Clone and Proxy Initialization
Clone/proxy instance state is initialized atomically through guarded `initialize()` functions. Implementation constructors disable initializers and may set checked immutable dependencies; they must not be mistaken for instance initialization. Plain non-proxy contracts use checked constructor configuration. Deployer remains the factory/upgrade authority on the configured blockchain.

---

## 📜 Smart Contract Inventory

| Smart Contract | Architecture | Role & Responsibility |
| :--- | :--- | :--- |
| **`JuvantiaAssetFabrica.sol`** | UUPS Upgradeable Proxy | Asset Factory entry point. Deploys and registers new `JuvantiaAsset` tokens. |
| **`JuvantiaAsset.sol`** | EIP-1167 Cloneable ERC-20 | Standard RWA asset token contract (18 decimal places, 100,000 total supply per asset). |
| **`JuvantiaTradeHub.sol`** | UUPS Upgradeable Proxy | Registered-share escrow; euro price per full share, integer ceiling for fills; unsold shares retain their seller's revenue rights. |
| **`JuvantiaRevenueDistributor.sol`** | Onchain accrual vault | Transfer-aware per-asset revenue with fractional remainders, attributed marketplace custody, and unified atomic tax/net revenue routing (`processPayment`) with `JuvantiaAerarium` tax deduction and payment replay protection. |
| **`JuvantiaAerarium.sol`** | Central treasury & tax catalog | Central tax registry (per-category basis points catalog) and owner-authorized spending with onchain purpose logging. |
| **`JuvantiaServicePayments.sol`** | Receipt-oriented payment gateway | Exact request/payer/recipient/amount events for backend entitlement verification. |
| **`community/ConsortiumTreasury.sol`** | Abstract clone-compatible foundation | Segregated operating/dividend funds, treasury-share exclusion and transfer/escrow-aware dividends. Not a complete Consortium contract. |

Consortium governance/Tribunal gate, Syndicate governance/points and both factories remain required. `ConsortiumTreasuryHarness` is test-only and must never be deployed as a production governance substitute.

### 4. Consortium Ledger Integration

A factory may register a fixed-supply `JuvantiaAsset` with a one-time `IAssetCheckpointObserver`. The RevenueDistributor validates the observer's share token and distributor, then calls it before every economic-ownership change, including escrow deposits/withdrawals. The observer cannot be rebound after asset registration. Ordinary device assets retain the existing observer-free registration path.

The Consortium dividend pool is reserved explicitly. `operatingBalance()` derives euro-token custody minus that reserve, so direct ERC-20 payments and permissionless device `claimFor` receipts become operating funds immediately without an indexer or keeper. Allocations and spending are internal until governed Consortium wrappers are implemented. Treasury shares remain non-dividend-bearing while attributed to the company in TradeHub escrow; sold shares earn only subsequent dividends.

---

## 📍 Deployment Status

No new configurable deployment has been performed. Full deployment requires all community contracts/factories, role wiring, ABI/address/deployment-block registry export and receipt-verified smoke tests. Never invent addresses or mark successful compilation as deployment.

---

## 🛠️ Developer Workflow Commands (Foundry)

- **Compile**: `forge build`
- **Run Unit Tests**: `forge test`
- **Configuration**: Solidity 0.8.30, Cancun, optimizer 200, 512 fuzz runs.
- **Deployment gate**: `DeployJuvantia.s.sol` requires explicit blockchain and euro-token environment variables, but still lacks full community deployment and canonical registry export. Do not broadcast a partial migration as the completed stack.
- **Confirmation**: Backend verifies the specific successful UserOperation and transaction receipt; no consensus-finality wait, webhook or permanent indexer.

---

## ⚠️ Storage Layout & Upgrade Mandates
When modifying upgradeable contracts (`JuvantiaAssetFabrica`, `JuvantiaTradeHub`):
- **Never modify existing storage variable order**. Always append new state variables to the bottom of the contract storage layout to prevent storage collisions during upgrades.
- **Always update the canonical deployment registry and [`DEPLOYMENTS.md`](DEPLOYMENTS.md)** immediately after receipt-verified deployments or upgrades.
