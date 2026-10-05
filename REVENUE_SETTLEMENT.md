# Central revenue custody

The universal protocol, integration examples, separate Consortium allocation tax, invoice proof
and coordinated release checklist are documented in [PAYMENT_PROTOCOL.md](PAYMENT_PROTOCOL.md).

TradeHub's legacy mapping remains private at storage slot 4. New order revisions/openedAt/expiry
and fill nonce are appended at slots 5–8. Existing Order fields are unchanged. Buyers approve and
pay Distributor directly. No TradeHub withdrawal or unfunded trade-credit gateway remains.

All shareholder mathematics, fractional remainders, transfer checkpoints and attributed escrow
are retained. Consortium treasury shares do not earn owner earnings. Net trading credits remain
separate from pooled earnings and are included in asset claims and claimAll. Other commercial
receipts and commissions use the addressed account ledger. No local Consortium owner-claim path
or second earnings index exists. Treasury operating spending cannot access the reserved owners' pool.
