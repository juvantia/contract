# Revenue and trade settlement

TradeHub executes share orders and holds the share escrow. RevenueDistributor
holds and pays asset revenue, seller-specific trade proceeds and Consortium
owners' revenue earnings. Consortium retains operating custody and allocation
governance; it does not maintain a separate earnings or payout engine.

## Consortium operating and distributed accounts

Incoming device earnings, commercial receipts and investment proceeds belong to
the Consortium's operating balance. After a revenue-distribution proposal reaches
the existing 75% approval threshold within its 36-hour window, the approved amount
is transferred atomically through `RevenueDistributor.distributeRevenue` for the
Consortium share token. This allocation does not impose a second service tax.

The second account's funds are physically held by RevenueDistributor.
`Consortium.distributablePool()` reads `totalDistributed - totalClaimed` for its
share token; trade proceeds are tracked separately. `totalAllocated` records only
the Consortium's governed allocations. Permissionless external revenue funding
can also add to that pool without accessing Consortium operating funds.

At asset registration, the authorized factory binds the matching Consortium as
its `revenueTreasury`. The binding is immutable and validated against the
treasury's share token and distributor. `revenueSupply` excludes all shares still
attributed to that treasury, including listed shares in TradeHub escrow.
`revenueBalanceOf` excludes the treasury's reserve while ordinary ownership and
voting reads retain `effectiveBalanceOf`. No distribution is possible when every
share belongs to the treasury.

The distributor's existing transfer/escrow checkpoints and fractional remainders
preserve owners' earnings across sales and contributions to the treasury.
Consortium no longer has `claim()`/`claimFor()` or a secondary checkpoint callback.
Its pool, index and claimable getters are read-only views over the distributor.
Owners receive earnings only through the distributor's claim methods. Operating
spending and Consortium judicial custody seizures cannot touch that reserve;
central judicial claims act on the actual beneficiary's earnings.

## Trade payment lifecycle

1. The buyer approves the euro token to TradeHub and calls `fillOrder`.
2. TradeHub collects the exact rounded-up price and checks its token balance delta.
3. TradeHub approves only that amount to RevenueDistributor and calls
   `depositTradeProceeds(asset, seller, amount)`. Only owner-authorized escrows can
   use this entry point; it checks the registered asset, beneficiary, positive
   amount and exact incoming token balance delta.
4. RevenueDistributor credits `tradeProceeds[asset][seller]` and the seller's
   aggregate `pendingTradeProceeds`, then emits `TradeProceedsDeposited`.
5. TradeHub releases the sold shares to the buyer. Any failure rolls back the
   entire payment, credit, order update and share transfer.

The seller receives the full trading price without tax or commission. Trade
proceeds do not update the reward-per-share index or give other shareholders an
entitlement. Escrowed unsold shares continue earning operating revenue for their
seller; a buyer receives only operating revenue accruing after acquisition.

## Unified claims and judicial enforcement

`claimable(asset, account)` includes unclaimed operating revenue and addressed
trade proceeds. Existing `claim(asset)`, `claimFor(asset, account)` and
`claimBatch(assets)` pay both in one transfer per asset. No shares need to remain
in the seller's account. Permissionless `claimFor` always pays the beneficiary.
Repeated assets in a batch cannot produce a duplicate payment.

Encumbrance blocks all ordinary claims. All judicial claim variants can seize
either kind of entitlement; a partial seizure consumes operating revenue first,
then trade proceeds. A failed token payout restores both ledgers atomically.
Revoking an escrow prevents new trade credits, while existing beneficiary claims
and share-order cancellations remain available.

## Audit and client compatibility

- `totalDistributed` and `totalClaimed` measure pooled revenue earnings, including
  approved Consortium owner allocations, independently of trade proceeds.
- `totalTradeDeposited` and `totalTradeClaimed` measure addressed trade proceeds.
- `RevenueClaimed` and `JudicialRevenueClaim` report the actual combined payout.
- `pendingTradeProceeds(account)` sums unclaimed trade proceeds across assets.
- TradeHub's `pendingWithdrawals(account)` delegates to that aggregate as a
  read-only compatibility view. It neither holds nor pays these proceeds.
- TradeHub no longer exposes `withdraw()` or emits `Withdrawal`.

Core's per-asset `claimable` reads and `claim`/`claimBatch` calldata remain valid.
Revenue discovery includes active Consortium ownership tokens and assets with a
nonzero claimable amount even when the account owns no shares. On-chain read
failures fail the summary instead of reporting a fabricated zero or partial balance.

## Deployment boundary

The legacy TradeHub mapping slot stays reserved in the original UUPS storage
position. This does not migrate any previously stored currency or entitlement.
The configured stack has no canonical deployment, and legacy economic state is
not a migration target. RevenueDistributor is not upgradeable; deployment of the
new coordinated stack and receipt-verified role wiring remain a separate release
operation. Do not upgrade a historical live marketplace onto this implementation
without a separately specified balance and dependency migration.

Consortium clones are not upgradeable. The new treasury layout and revenue binding
apply to fresh, coordinated deployments; existing clones and old secondary-ledger
balances are not migrated by compilation or by updating the factory source.
