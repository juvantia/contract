# Chiado deployment readiness

Reviewed and corrected: 2026-10-24. Original audited source: `fd4528b`.
Original findings and ten unsafe-behavior reproductions remain in
[audit history](https://github.com/juvantia/contract/tree/89b2c91/audit).

**Source corrections are implemented and locally verified. A Chiado broadcast is not ready
until the actual release configuration and network simulation are verified.**
No deployment transaction has been sent and no canonical address or receipt is asserted.

## Verification

- `forge fmt --check`, `forge build --sizes`, `forge test`: **172 tests passed**.
- Configured fuzzing uses 512 runs. New judicial custody fuzzing combines a partial trade,
  protected share custody, a seller-specific fine, unrelated account credit and pooled revenue.
- Full deployment simulation verifies all 15 components/implementations/proxies, owners,
  token/Registry/budget/Distributor bindings, issuer, Tribunal, source roles and registrars.
  This runs locally with a test ERC-20 and chain ID 10200, not on a live Chiado fork.
- Deployment tests reject incorrect chain/token/decimals/signers/Tribunal before deployment.
  Registry tests preserve authenticated same-block quotes, stale-time rejection and expiry.
- Shell syntax and stubbed default-simulation/explicit-broadcast behavior were checked.
- Independent review of the Consortium and Syndicate changes found no remaining concrete issue.
- Build still emits existing Forge lint warnings; compilation is not a claim of a clean static audit.

With pinned Solidity 0.8.30, Cancun and optimizer 200:

| Runtime contract | Bytes | EIP-170 margin |
| --- | ---: | ---: |
| JuvantiaAsset | 7,037 | 17,539 |
| JuvantiaRevenueDistributor | 21,328 | 3,248 |
| Consortium | 17,422 | 7,154 |
| Syndicate | 24,357 | 219 |

Syndicate is close to the size limit. Preserve the build size gate for any subsequent change.

## Closed source findings

| Finding | Correction | Regression evidence |
| --- | --- | --- |
| H1: judicial transfer emptied attributed escrow and duplicated revenue rights | Asset transfers cannot reduce physical custody below attributed escrow, even after escrow revocation. Exceptional direct APU seizure remains available from user wallets, including smart accounts. New `judicialClaimTrade` recovers only a debtor's EURO trade proceeds. | [JudicialCustody.t.sol](../test/JudicialCustody.t.sol) |
| H2: the same transferred shares could vote repeatedly | Consortium uses physical ownership and voting-supply snapshots from the same completed block before proposal creation. Treasury holdings are excluded at that snapshot. | [ConsortiumGovernance.t.sol](../test/ConsortiumGovernance.t.sol) |
| H3: rank demotion bypassed cofounder protection | Demotions use current-rank kick protection; Grade 6 requires 80% of eligible others. Admissions/promotions use the target rank. Zero-threshold low-grade admission remains Primus-only across all paths. | [SyndicateGovernance.t.sol](../test/SyndicateGovernance.t.sol) |
| H4: stale kicks corrupted member enumeration or removed the current Primus | Snapshot vote weights/eligible base, membership incarnations and target/leadership versions prevent stale execution and leave/rejoin voting. Execution revalidates membership and role. | [SyndicateGovernance.t.sol](../test/SyndicateGovernance.t.sol) |
| H5: incorrect spending thresholds and compiled initial amounts | Petty expenses require at least 50.001%; Major expenses and unified package changes require at least 65%. Initial monetary limits are signed in the creation voucher. The unilateral Consortium spend selector fails closed. | [ConsortiumGovernance.t.sol](../test/ConsortiumGovernance.t.sol) |
| M1: same-block rule publication invalidated an authentic older quote | Authenticated quotes accept `issuedAt == supersededAt`; later timestamps, expiry and issuer checks remain enforced. | [RegistryQuoteBoundary.t.sol](../test/RegistryQuoteBoundary.t.sol) |
| M2: contradictory signers or zero Tribunal were accepted | Shared preflight validates the explicit release configuration. Both Core roles use one identity; owner/Core/Tribunal are distinct and nonzero. Full and standalone community scripts validate before broadcast recording. | [DeploymentReadiness.t.sol](../test/DeploymentReadiness.t.sol) |

The original unsafe-behavior tests are retired; normal tests now assert the safe outcome.
See [their historical record](chiado-2026-10-24/README.md).

## Accepted policy and interface changes

The owner's session decisions supersede older conflicting Notion descriptions:

- Tribunal may exceptionally seize APU directly from a user's wallet. EURO fines against
  marketplace proceeds debit that particular seller's monetary ledger in Distributor.
  They do not take the shares collateralizing other marketplace positions.
- Consortium ownership snapshots replace live-balance voting; votes require no delegation
  and shares stay transferable. Snapshots concern physical ERC-20 ownership, as the prior
  voting specification did; revenue's attributed escrow accounting remains separate.
- Election approval remains strictly greater than 50.001%; expense approval is at least
  50.001% for Petty and at least 65% for Major. Allocation/private treasury-sale approval
  remains at least 75%. All Consortium proposals retain their 36-hour deadline.
- Owners select initial monetary settings. `pettyLimit` is the absolute per-operation
  Petty boundary and `majorLimit` is the absolute approved-expense cap. Require
  `0 < pettyLimit <= majorLimit`. Later whole-package changes need at least 65%, consistent
  with [Notion](https://app.notion.com/p/3b7fbac38ebd818b8c39f120bba07dea).
  Open expense proposals preserve their category/revision, expense tier and cap.
- Consortium initializer now takes eight arguments. Its factory voucher/EIP-712 hash includes
  `pettyLimit` and `majorLimit` after `treasuryShares`. Existing proposal enum values 0-4
  are preserved; `PettyExpenditure` is appended as 5.
- Syndicate keeps its existing function/action tuples. It adds custom errors for stale actions,
  ineligible voters and unsupported token decimals. Unknown/stale/executed threshold queries
  revert. Its existing 500/25,000 monetary defaults now scale actual token decimals.
- Supported token decimals are 0-72. Tests use actual six-decimal ERC-20 implementations.
  No token symbol is queried. Monetary limits and amounts are integer base units.
- Existing storage fields retain their order. Asset history and community governance state
  are appended. TradeHub's reserved and appended UUPS slots remain unchanged.

The current Solidity interfaces are described in [PAYMENT_PROTOCOL.md](../PAYMENT_PROTOCOL.md).
A fresh configured stack is required; existing immutable contracts and EIP-1167 clones are
not upgraded by changing their factories.

## Remaining release gates

1. Supply the approved release configuration. The current contract environment has none:
   `BLOCKCHAIN_CHAIN_ID=10200`, `BLOCKCHAIN_RPC_URL`, `EURO_TOKEN_ADDRESS`,
   `EURO_TOKEN_DECIMALS`, `DEPLOYER_ADDRESS`, the same public Core address in both issuer
   and authorizer settings, and a separate `TRIBUNAL_ADDRESS`. Private keys stay in the
   encrypted Foundry keystore/Core secrets. See [.env.example](../.env.example).
2. Verify the actual Chiado RPC/token/code/decimals and expected deployment signer. Run
   `./deploy.sh` with the approved environment: it simulates by default using the public
   sender and does not need to unlock the signing account. The mock-token
   full-stack test is not a substitute for this actual-network rehearsal.
3. After explicit authorization, broadcast using `./deploy.sh --broadcast`. The wrapper
   rejects `--skip-simulation` and `--resume`; recovery of a partial broadcast requires
   checking its actual receipts separately. Verify every successful receipt, implementation and binding.
4. Export matching ABIs plus receipt-verified addresses and deployment blocks for Core/Admin,
   then update the canonical deployment record from those receipts. Simulation output is
   never a canonical record.
5. Publish the selected category/tax revisions, including private zero-charge principal rules,
   and confirm real invoice/trade/allocation/claim/replay/expiry receipts before activation.

## Feature and integration scope

The corrections above close the agreed source defects, not all deferred community features:

- Core organization consent, creation receipt verification and organization-as-payer flows
  remain deferred in [Core readiness](../../core/docs/DEPLOYMENT_READINESS.md).
  Before enabling creation, update its voucher ABI/signing to include the monetary package.
  Old vouchers fail closed; do not enable the old workflow against this factory.
- Public Consortium treasury listing, coordinated top-up proposals and dissolution workflows
  remain separate work. Syndicate's full governed major-spending workflow remains absent;
  the existing petty gateway is unchanged by the Consortium-specific expense policy.
- Owner-configured Consortium monetary limits currently use absolute base units per operation;
  percentage-based or periodic budgets are not implemented.
- Asset naming format is trusted administration/Core policy. Fabrica enforces existing parent
  and unique nonzero ID, not a textual `DM-XXXX-C{N}` format inside hashed IDs.
- No old clones, balances, account bindings or economic state migrate automatically.
  Contract deployment does not establish server activation or a native binary/OTA release.

Chiado is a test deployment for further acceptance. These remaining scope items must not be
advertised as implemented or activated.
