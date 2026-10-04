# Revenue and trade settlement

TradeHub executes share orders and holds the share escrow. RevenueDistributor
holds and pays both asset operating revenue and seller-specific trade proceeds.
Consortium operating allocations and corporate revenue claims retain their
current separate governance and accounting until the next implementation phase.

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

- `totalDistributed` and `totalClaimed` measure only operating revenue.
- `totalTradeDeposited` and `totalTradeClaimed` measure addressed trade proceeds.
- `RevenueClaimed` and `JudicialRevenueClaim` report the actual combined payout.
- `pendingTradeProceeds(account)` sums unclaimed trade proceeds across assets.
- TradeHub's `pendingWithdrawals(account)` delegates to that aggregate as a
  read-only compatibility view. It neither holds nor pays these proceeds.
- TradeHub no longer exposes `withdraw()` or emits `Withdrawal`.

Core's existing per-asset `claimable` reads and `claim`/`claimBatch` calldata remain
valid. Revenue discovery must include assets with a nonzero claimable amount even
when the account owns no shares, as the current Core summary already does.

## Deployment boundary

The legacy TradeHub mapping slot stays reserved in the original UUPS storage
position. This does not migrate any previously stored currency or entitlement.
The configured stack has no canonical deployment, and legacy economic state is
not a migration target. RevenueDistributor is not upgradeable; deployment of the
new coordinated stack and receipt-verified role wiring remain a separate release
operation. Do not upgrade a historical live marketplace onto this implementation
without a separately specified balance and dependency migration.
