# Central revenue custody

The business model is [Core PAYMENTS.md](../core/docs/PAYMENTS.md): seller price/category,
one beneficiary, tax only, and separate Consortium owners' allocation.
Current interfaces and invoice proof are documented in [PAYMENT_PROTOCOL.md](PAYMENT_PROTOCOL.md).
Extra commission fields below describe current source and require alignment before activation.

TradeHub's legacy mapping remains private at storage slot 4. New order revisions/openedAt/expiry
and fill nonce are appended at slots 5–8. Existing Order fields are unchanged. Buyers approve and
pay Distributor directly. No TradeHub withdrawal or unfunded trade-credit gateway remains.

All shareholder mathematics, fractional remainders, transfer checkpoints and attributed escrow
are retained. Consortium treasury shares do not earn owner earnings. Net trading credits remain
separate from pooled earnings and are included in asset claims and claimAll. Other commercial
receipts and commissions use the addressed account ledger. No local Consortium owner-claim path
or second earnings index exists. Treasury operating spending cannot access the reserved owners' pool.
