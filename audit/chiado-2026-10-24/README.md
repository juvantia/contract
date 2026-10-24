# Original audit reproductions

The original ten reproductions asserted unsafe behavior at the source baseline. They are
preserved in [audit commit 89b2c91](https://github.com/juvantia/contract/tree/89b2c91/audit/chiado-2026-10-24).
They are no longer runnable against corrected contracts and are superseded by normal,
expected-safe regression tests:

- [JudicialCustody.t.sol](../../test/JudicialCustody.t.sol): escrow solvency, direct APU recovery,
  seller-specific EURO fines and completed-block ownership history.
- [ConsortiumGovernance.t.sol](../../test/ConsortiumGovernance.t.sol): voting snapshots,
  expense thresholds and signed owner-selected spending packages.
- [SyndicateGovernance.t.sol](../../test/SyndicateGovernance.t.sol): protected ranks,
  consistent voting weights and stale member/leadership actions.
- [RegistryQuoteBoundary.t.sol](../../test/RegistryQuoteBoundary.t.sol): authenticated same-block
  historical quotes, expiry and revocation.
- [DeploymentReadiness.t.sol](../../test/DeploymentReadiness.t.sol): complete stack simulation,
  cross-contract bindings and release preflight rejection.

Run `forge test` from the repository root. There is no separate green-known-defect suite.
See [the current readiness review](../CHIADO_READINESS.md) for deployment boundaries.
