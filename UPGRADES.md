# Contract upgrades and fixed instances

Owner clarification: 2026-10-26. A created asset, Consortium or Syndicate retains the contract
logic with which it was created. A particular organization is never upgraded through a change
to its factory. Existing membership, voting and permitted settings remain mutable under that
original logic. Do not add an instance/beacon upgrade mechanism.

Common financial services must support logic updates while retaining their addresses and state.
RevenueDistributor, Aerarium and PaymentRegistry therefore use the same ERC-1967/UUPS model
as Fabrica, TradeHub and both community factories. The current owner authorizes upgrades;
the Core invoice signer, representatives and Tribunal acquire no upgrade authority.

## Financial proxy initialization

Deploy each implementation with a no-argument constructor that disables its initializers.
Deploy its ERC1967Proxy with the complete initializer calldata in the proxy constructor:

- RevenueDistributor.initialize(token,owner,aerarium): token and owner state, EIP-712 name
  JuvantiaRevenueDistributor/version 2, and the treasury link.
- Aerarium.initialize(token,owner): payment token and budget authority.
- PaymentRegistry.initialize(owner): rule publication and upgrade authority.

Registry, budget and registrar/source wiring remains checked after initialization. No tax
categories or tariffs are invented. Token addresses are persistent proxy state. EIP-712 uses
the proxy as verifyingContract; a compatible implementation upgrade keeps valid outstanding
invoices, issuer permissions, replay protection and the domain unchanged.

The pinned OpenZeppelin 5.5 ReentrancyGuard is stateless and uses its own namespace. It accepts
the unentered zero status of a fresh proxy and sets the guard before external token calls;
economic/reentrancy regressions run through the same proxies as deployment. Ownable,
Initializable and EIP-712 use their pinned OpenZeppelin namespaces.

## Compatibility checks before upgrading

Keep every existing slot, offset, type and nested mapping/struct shape. PaymentSettlement's
base layout is frozen: new Distributor state belongs at the bottom of the concrete contract,
so adding a base field cannot shift its existing monetary ledgers. Registry history and Rule/
Version shapes must remain compatible. Future changes must preserve owner/issuer authority,
actual token bindings, historical quotes, revenue checkpoints, custody and replay protection.

Run the economic and upgrade tests, formatting, size gate and storage check:

```sh
forge fmt --check
forge test
forge build --sizes
python3 script/check_storage_layout.py
python3 -m unittest discover -s test -p 'test_storage_layout.py'
```

The storage checker compares against `storage-layout/infrastructure-v1.json`. It ignores
unstable AST IDs, checks old entries recursively and allows new state at the end only. It also
pins clean OpenZeppelin submodules: changing those dependencies requires a separate review
of their namespaced layouts. This is a storage check, not a semantic or security audit.

For a separately named proposed implementation:

```sh
python3 script/check_storage_layout.py --candidate JuvantiaRevenueDistributor=src/JuvantiaRevenueDistributorV2.sol:JuvantiaRevenueDistributorV2
```

After a compatible release, `--record` can extend the reviewed baseline; it refuses to remove
or modify existing fields. Never regenerate it to conceal an incompatible change. The CI job
runs checks only; on-chain deployment remains an explicit Foundry operation, as requested.

The owner deploys the reviewed implementation, checks its code and then calls the existing
proxy's upgradeToAndCall(newImplementation,data). Optional reinitialization of new fields must
be versioned and owner-authorized. Verify the successful receipt, unchanged proxy address,
actual ERC-1967 implementation, explorer sources and relevant state before recording an upgrade
in DEPLOYMENTS.md. Preserve original creation evidence separately from upgrade receipts.

## Tested preservation

The full suite includes nine upgrade regressions. They retain addressed and pooled earnings,
fractional remainders, paid IDs/private funding nonce, source/registrar grants, attributed trade
escrow and sale proceeds, encumbrances, old signed invoices and EIP-712 digest, issuer grants,
published revisions and historical windows, tax custody and the budget spending counter.
Payouts, cancellation and new settlements continue after the upgrade. Invalid targets,
unauthorized callers, repeated initialization and failed reinitialization are rejected; a failed
upgrade rolls back its implementation change. A separate test proves the original Asset,
Consortium and Syndicate clone code and state remain unchanged after all three shared upgrades.

Current runtime sizes with Solidity 0.8.30/Cancun/optimizer 200: Distributor 23,607 bytes
(969-byte EIP-170 margin), Aerarium 6,008 and Registry 6,506. The test Distributor V2 is 23,906;
Syndicate remains 24,357. Preserve the size gate for every proposed implementation.

## Initial transition from the earlier ordinary deployment

The 2026-10-25 financial contracts were ordinary contracts and cannot be converted to proxies
at their existing addresses. This source revision prepares seventeen components, including
seven proxy/implementation pairs, and thirty deployment/configuration transactions. The three
fixed templates are Asset, Consortium and Syndicate. Code for those instances is unchanged.

Before replacing the canonical test stack, check actual on-chain assets, orders, organizations,
held funds and financial rules and Core's payment workflows. Do not abandon populated state
or change immutable instances' bound service addresses. Any populated deployment needs an
explicit migration design. The empty test stack can be replaced without economic migration.
Keep the previous address/ABI/receipt/explorer/runtime evidence in the archive. Update Core's
persistent configuration only after receipt/runtime/binding verification of the new proxies.
Reuse the same Core service identity and keep Tribunal/community creation disabled.

Only [DEPLOYMENTS.md](DEPLOYMENTS.md) and its canonical receipt registry establish activation;
implementation and local tests do not by themselves establish an on-chain transition.
