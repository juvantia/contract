# Chiado deployment readiness review

Reviewed: 2026-10-24. Source baseline: `fd4528b56875f218659ff15e0e290c998c606c10`.

**Decision: do not deploy this revision as the canonical Chiado stack.** The existing
108 tests pass, but the additional reproductions demonstrate insolvency after a Tribunal
escrow transfer, reusable Consortium voting power, and broken Syndicate governance.
These defects remain open; this review changes no runtime contracts and sends no transactions.

Chiado is the owner's selected test network, chain ID **10200**. A read-only call to its
public RPC returned 10200 during this review. The configured Cancun EVM target is supported
by Chiado's [Dencun upgrade](https://docs.gnosischain.com/about/specs/hard-forks/dencun).
See the [official network record](https://docs.gnosischain.com/about/networks/chiado).
The payment token, actual decimals and temporary Tribunal identity still need release selection.

## Scope and evidence

Reviewed all settlement, asset, marketplace and community runtime contracts, the four
deployment scripts, `deploy.sh`, Foundry configuration and existing tests. Requirements were
searched and fetched from Notion, including the sources linked with the findings below.
Relevant Core activation documentation was read; this is not a fresh audit of Core/API/native code.

Baseline verification: `forge fmt --check`, `forge build --sizes`, and `forge test` pass;
the default suite has 108 passing tests, including the configured 512-run fuzz tests.
Build emits existing Forge lint warnings; passing compilation is not a clean static-analysis result.
Largest runtime contracts are Syndicate (22,365 bytes) and RevenueDistributor (20,712 bytes),
both below the 24,576-byte EIP-170 limit. TradeHub inspection confirms legacy slots 0-4
and appended fields at slots 5-9.

The separate reproduction suite passes all 10 cases. Reproductions are in
[chiado-2026-10-24](chiado-2026-10-24/). Run from the repository root:

```sh
FOUNDRY_TEST=audit/chiado-2026-10-24 forge test --match-test '^testAudit'
forge fmt --check audit/chiado-2026-10-24
```

**A passing audit reproduction confirms the defect exists.** These tests assert the current
incorrect behavior and are deliberately separate from the default regression suite. When fixing
a finding, move its scenario into the normal suite and assert the intended safe outcome instead.
All addresses, keys and balances in these tests are local fixtures, not release configuration.

## Findings

### H1 — Tribunal transfers can make the shared Distributor insolvent

Affected: [JuvantiaAsset.sol](../src/JuvantiaAsset.sol), `judicialTransfer`, `judicialSeize`;
[JuvantiaRevenueDistributor.sol](../src/JuvantiaRevenueDistributor.sol), `effectiveBalanceOf`,
`escrowDeposit`, `escrowWithdraw`, `checkpointTransfer`;
[JuvantiaTradeHub.sol](../src/JuvantiaTradeHub.sol), order custody.

A Tribunal transfer from TradeHub moves physical shares without clearing the seller's attributed
escrow position or adjusting its order. The seller and seizure recipient then both earn on
the same shares. The reproduction lists Alice's 100,000 APU, transfers TradeHub custody to Bob,
funds Carol's unrelated account with 100 token units and the asset pool with another 100,
then successfully pays Alice 100 and Bob 100. `totalClaimed` becomes 200 against
`totalDistributed` of 100. Carol's account credit can no longer be collected, and cancelling
Alice's order reverts. This requires an authorized Tribunal operation, not an arbitrary caller.

Conversely, a judicial transfer directly from the listed seller fails because the physical
shares are held by TradeHub. Ordinary seller-targeted seizure cannot reach listed ownership.

Required: an atomic, escrow-aware judicial route that reconciles the selected seller/order,
custody, revenue checkpoints and beneficial ownership. Prevent unreconciled transfers out of
attributed custody. Clamping a negative effective balance alone does not remove duplicate
seller entitlement. Test solvency across account credits, multiple asset pools and trade proceeds.

Proofs: `testAuditJudicialTransferFromEscrowDuplicatesRevenueAndStealsOtherCredits` and
`testAuditDirectSellerSeizureCannotReachListedShares`.

### H2 — The same Consortium shares can vote repeatedly

Affected: [Consortium.sol](../src/community/Consortium.sol), `castVote`, `_isThresholdMet`.

`hasVoted` protects an address, while vote weight is its current freely transferable share
balance. A holder of 25% of circulating shares votes, transfers the same shares to a second
address, votes again, then repeats with a third address. The reproduction elects that minority
holder as Magister. Other financial proposal thresholds can be crossed the same way.
The denominator also uses live circulating supply, without a proposal-bound snapshot.

Required decision: snapshot ownership/supply or lock voting shares for the proposal.
The [Consortium task](https://app.notion.com/p/3d7fbac38ebd81629117d679f493ccd0)
is marked Done but its voting-transfer protection acceptance item is unchecked.
The [business specification](https://app.notion.com/p/3b7fbac38ebd818b8c39f120bba07dea)
currently describes live balances, so switching to snapshots needs an explicit policy decision.
The owner was asked which model to adopt.

Proof: `testAuditSameSharesVoteThreeTimesToElectMinorityCandidate`.

### H3 — Syndicate grade changes bypass cofounder protection

Affected: [Syndicate.sol](../src/community/Syndicate.sol), `changeGrade`, `proposeAction`,
`_isActionThresholdMet`, `_changeGrade`.

Primus can lower a Grade-6 cofounder to Grade 1/2 without a vote, then remove that member
under the much lower kick threshold. More seriously, any member can propose a ChangeGrade
action to Grade 1/2: the admission threshold for the new grade is zero, so it executes
immediately. The reproduction lets a Grade-1 member demote a Grade-6 cofounder.

This defeats the [Syndicate cofounder-protection requirement](https://app.notion.com/p/3b7fbac38ebd8117bd28e180c4fddd6a):
one equal cofounder must not unilaterally displace another. The permission on direct
`changeGrade` does not protect the generic proposal entry point.

Required: distinguish promotion/admission from demotion, enforce protected-rank authorization
on every entry point, and test that lowering rank cannot bypass the original member protection.

Proofs: `testAuditPrimusDemotesAndKicksEqualCofounderWithoutApproval` and
`testAuditAnyMemberCanUnilaterallyDemoteCofounderThroughAction`.

### H4 — Stale Syndicate kick actions corrupt membership or remove the current Primus

Affected: [Syndicate.sol](../src/community/Syndicate.sol), `supportAction`, `_executeAction`,
`_removeMember`.

Kick validity is checked at proposal creation, but not at execution. If the target leaves
before an old action gains support, `_removeMember` runs again with a deleted index. It pops
an unrelated member from `members` while leaving that member's active flag and weight set.
The reproduction leaves two active membership flags and total weight 64, but only one
enumerated member. Proportional quota collection then uses inconsistent membership data.

If the target becomes Primus after the kick proposal opens, executing the old proposal
removes the current Primus's membership and Grade 6 while leaving `primus` pointing to it.

Required: revalidate target membership and role at execution, make `_removeMember` enforce
its own invariants, and invalidate/version actions when membership or protected roles change.
Stored vote weight and the live eligible-weight denominator also need a consistent policy.

Proofs: `testAuditStaleKickRemovesAnotherMemberFromEnumeration` and
`testAuditStaleKickCanRemoveCurrentPrimus`.

### H5 — Consortium spending approval is weaker than the Notion requirement

Affected: [Consortium.sol](../src/community/Consortium.sol), `_isThresholdMet`,
`SpendingLimitsPackage`, `MajorExpenditure`, initial limits.

The [business specification](https://app.notion.com/p/3b7fbac38ebd818b8c39f120bba07dea)
and [contract specification](https://app.notion.com/p/3b9fbac38ebd81b5a94ac80faf2c0d1c)
require at least 65% approval for the spending-limits package. Code groups it with elections
and major expenditure at greater than 50.001%. A reproduction changes limits with only 60%
of circulating supply, without exploiting H2.

Code implements two absolute limits, Petty/Major; creation vouchers cannot supply initial
limits. Notion contains both Petty/Major and Petty/Standard/Major descriptions and records
spending-package choices as unresolved. MajorExpenditure also uses the lower election threshold.

Required decision: confirm the package, initial configuration and approval thresholds before
changing the ABI/governance. The owner was asked to select the intended package.

Proof: `testAuditSixtyPercentCanChangeLimitsDespiteSixtyFivePercentRequirement`.

### M1 — A same-block rule update invalidates an otherwise valid frozen quote

Affected: [JuvantiaPaymentRegistry.sol](../src/JuvantiaPaymentRegistry.sol), `quotedRule`.

`issuedAt < supersededAt` rejects an order or invoice legitimately created before another
transaction publishes a new revision in the same block: both timestamps are equal. The
reproduction opens an order, publishes the next revision at the same timestamp, and observes
`Stale quote` on its fill. Cancellation remains possible.

This conflicts with preserving already-issued terms until expiry in the
[Universal Payment Protocol](https://app.notion.com/p/3f1fbac38ebd81b9862bd6594308ddb1).
Required: define the same-block boundary and test it for orders, signed invoices and proposals.
Accepting equality is a possible correction within the existing trusted issuer/source model;
keep the historical revision authentication and TTL checks.

Proof: `testAuditQuoteCreatedBeforeSameBlockRulePublicationBecomesUnfillable`.

### M2 — Deployment accepts contradictory signing roles and disabled Tribunal wiring

Affected: [DeployJuvantia.s.sol](../script/DeployJuvantia.s.sol),
[DeployCommunities.s.sol](../script/DeployCommunities.s.sol), [.env.example](../.env.example).

The full deployment accepts different invoice-issuer and community-authorizer addresses,
although the [current protocol](https://app.notion.com/p/3b9fbac38ebd816cbb22c1b750685ad9)
requires one Core identity. It also accepts the zero Tribunal address throughout the stack.
The local full-script reproduction verifies both configurations succeed.

The standalone community script defaults the authorizer to the deployer and Tribunal to zero.
The environment example omits the issuer, authorizer and Tribunal settings used by the full
script and provides a default decimal value without verifying the token. There is no generated
receipt-verified ABI/address/deployment-block export step.

Required: validate the complete selected release configuration before broadcast, assert the
shared Core signer and intended owner/Tribunal separation, and verify actual token decimals.
Prepare a receipt-based manifest/export and binding checks. Do not use a standalone partial
script as evidence that the complete stack is ready. A temporary test Tribunal identity is a
release choice; the script does not deploy a constitution/jury system.

Proof: `testAuditScriptAcceptsDifferentCoreSignersAndDisabledTribunal`.

## Functional gaps and release boundaries

- **Token decimals:** Consortium initializes monetary limits with `1_000 ether`/`50_000 ether`,
  Syndicate with `500 ether`/`25_000 ether`, assuming an 18-decimal payment token. For a token
  with 6 decimals these limits are 10^12 times too high in whole-token terms. Either restrict
  and verify an 18-decimal token for this release or derive/configure monetary limits from
  actual token decimals. The 18-decimal APU supply itself is intentional and independent.
- **Community features:** Tribunal-gated Consortium dissolution, Syndicate dissolution,
  coordinated treasury top-ups and the Consortium public TradeHub-listing wrapper are absent.
  Syndicate `majorLimit` is stored but has no ordinary governed major-spending execution path;
  its action enum handles membership, grades and leadership only. Initial spending packages
  are not carried by either factory voucher. These features must be implemented or explicitly
  excluded from the Chiado acceptance scope. The public listing gap is already documented
  in [Notion](https://app.notion.com/p/3b9fbac38ebd816cbb22c1b750685ad9).
- **Asset identifiers:** `createSubAsset` enforces an existing parent and unique nonzero ID,
  not the `DM-XXXX-C{N}` naming format described in local instructions. Clarify that naming
  validation belongs to trusted administration/Core, or implement the intended restriction.
- **Integration activation:** Core's existing [readiness record](../../core/docs/DEPLOYMENT_READINESS.md)
  defers organization creation/consent/creation-receipt checks and organization-as-payer flows;
  it also records configuration, chain-schema and trade-placeholder gaps. Contract deployment
  does not resolve them. Keep deferred workflows disabled until separately verified.
- **Upgrade scope:** RevenueDistributor, Registry and Aerarium are not UUPS proxies. Existing
  asset/community EIP-1167 clones do not upgrade when a factory implementation changes.
  Fixing deployed instances may require a fresh test stack; factory upgradeability alone is
  not a recovery mechanism for all of these defects.

## Conditions to reverse the decision

1. Resolve H1-H4 and add regression/invariant coverage for custody conservation, shared-vault
   solvency, one effective vote per share, protected ranks and membership enumeration.
2. Confirm H5 governance policy, decimals and the required community feature scope. Correct
   M1 and add the M2 deployment preflight checks.
3. Run formatting, build/sizes and the complete normal suite after corrections. Re-run each
   scenario as an expected-safe regression, then simulate the full selected stack against
   Chiado with the actual token/configuration and no broadcast.
4. After an explicitly authorized deployment, verify successful receipts, implementations,
   ownership, Tribunal, registrars, escrow, source masks and the single Core signing identity.
   Export actual ABIs/addresses/blocks and update the canonical deployment record from receipts.
5. Publish the selected categories/tax revisions, including private zero-charge principal
   rules, and verify actual invoice, trade, owners' allocation, claim and replay/expiry receipts.
   Verify Core/native financial activation separately for the approved release scope.

No canonical address, transaction hash, deployment block or live migration is asserted here.
