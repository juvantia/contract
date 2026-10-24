#!/usr/bin/env python3
"""Verify a Foundry full-stack broadcast against RPC before exporting public artifacts."""

import hashlib
import json
from pathlib import Path
import sys
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
IMPLEMENTATION_SLOT = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
ZERO = "0x" + "0" * 40


def require(condition, reason):
    if not condition:
        raise RuntimeError(reason)


def main():
    require(len(sys.argv) == 3, "Usage: verify_deployment.py BROADCAST_JSON OUTPUT_DIRECTORY")
    broadcast = json.loads(Path(sys.argv[1]).read_text())
    output = Path(sys.argv[2])
    settings = {}
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            settings[key.strip()] = value.strip().strip("\"'")

    def rpc_batch(calls):
        results = []
        for offset in range(0, len(calls), 15):
            chunk = calls[offset : offset + 15]
            body = [{"jsonrpc": "2.0", "id": i, "method": m, "params": p} for i, (m, p) in enumerate(chunk)]
            request = urllib.request.Request(
                settings["BLOCKCHAIN_RPC_URL"],
                data=json.dumps(body).encode(),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            require(isinstance(payload, list) and len(payload) == len(chunk), "Incomplete RPC batch")
            indexed = {item["id"]: item for item in payload}
            require(len(indexed) == len(chunk), "Duplicate RPC response IDs")
            for i in range(len(chunk)):
                item = indexed[i]
                require("error" not in item and "result" in item, "RPC failure: " + chunk[i][0])
                results.append(item["result"])
        return results

    chain = int(rpc_batch([("eth_chainId", [])])[0], 16)
    require(chain == int(settings["BLOCKCHAIN_CHAIN_ID"]) == broadcast["chain"], "Chain mismatch")
    txs = broadcast["transactions"]
    require(len(txs) == 29 and not broadcast["pending"], "Full broadcast is incomplete")
    require(all(tx.get("hash") for tx in txs), "Missing transaction hash")
    require(len({tx["hash"] for tx in txs}) == len(txs), "Duplicate transaction hash")
    receipts = rpc_batch([("eth_getTransactionReceipt", [tx["hash"]]) for tx in txs])
    owner = settings["DEPLOYER_ADDRESS"].lower()
    for tx, receipt in zip(txs, receipts):
        require(receipt is not None and int(receipt["status"], 16) == 1, "Missing or failed receipt")
        require(receipt["transactionHash"].lower() == tx["hash"].lower(), "Receipt transaction mismatch")
        require(receipt["from"].lower() == owner, "Unexpected transaction sender")
    blocks = sorted({receipt["blockNumber"] for receipt in receipts}, key=lambda value: int(value, 16))
    headers = rpc_batch([("eth_getBlockByNumber", [block, False]) for block in blocks])
    headers_by_number = dict(zip(blocks, headers))
    for receipt in receipts:
        header = headers_by_number[receipt["blockNumber"]]
        require(header and header["hash"] == receipt["blockHash"], "Receipt block is not canonical")
        require(receipt["transactionHash"] in header["transactions"], "Transaction absent from block")
    block_tag = blocks[-1]

    # CREATE order is fixed by DeployJuvantia.run(); proxy records use their implementation ABI.
    inventory = [
        ("aerarium", "JuvantiaAerarium", False),
        ("revenue", "JuvantiaRevenueDistributor", False),
        ("registry", "JuvantiaPaymentRegistry", False),
        ("assetImplementation", "JuvantiaAsset", False),
        ("fabricaImplementation", "JuvantiaAssetFabrica", False),
        ("fabrica", "JuvantiaAssetFabrica", True),
        ("tradeImplementation", "JuvantiaTradeHub", False),
        ("trade", "JuvantiaTradeHub", True),
        ("services", "JuvantiaServicePayments", False),
        ("consortiumImplementation", "Consortium", False),
        ("consortiumFactoryImplementation", "ConsortiumFactory", False),
        ("consortiumFactory", "ConsortiumFactory", True),
        ("syndicateImplementation", "Syndicate", False),
        ("syndicateFactoryImplementation", "SyndicateFactory", False),
        ("syndicateFactory", "SyndicateFactory", True),
    ]
    creations = [(tx, receipt) for tx, receipt in zip(txs, receipts) if tx["transactionType"] == "CREATE"]
    require(len(creations) == len(inventory), "Unexpected CREATE inventory")
    artifacts, contracts = {}, {}

    def artifact(name):
        if name not in artifacts:
            artifacts[name] = json.loads((ROOT / "out" / (name + ".sol") / (name + ".json")).read_text())
        return artifacts[name]

    for (role, name, proxy), (tx, receipt) in zip(inventory, creations):
        require(tx["contractName"] == ("ERC1967Proxy" if proxy else name), "Unexpected CREATE order")
        address = receipt["contractAddress"].lower()
        require(address == tx["contractAddress"].lower(), "CREATE receipt address mismatch")
        contracts[role] = {
            "address": address,
            "contract": name,
            "transactionHash": receipt["transactionHash"],
            "deploymentBlock": int(receipt["blockNumber"], 16),
            "abi": "abi/" + name + ".json",
        }
    require(len({c["address"] for c in contracts.values()}) == 15, "Duplicate deployment address")
    codes = rpc_batch([("eth_getCode", [contracts[role]["address"], block_tag]) for role, _, _ in inventory])
    for (role, name, proxy), code in zip(inventory, codes):
        deployed = artifact("ERC1967Proxy" if proxy else name)["deployedBytecode"]
        actual = bytearray.fromhex(code.removeprefix("0x"))
        compiled = bytearray.fromhex(deployed["object"].removeprefix("0x"))
        require(actual and len(actual) == len(compiled), "Runtime length mismatch: " + role)
        contracts[role]["runtimeBytecodeSha256"] = hashlib.sha256(actual).hexdigest()
        for references in deployed.get("immutableReferences", {}).values():
            for reference in references:
                start, length = reference["start"], reference["length"]
                actual[start : start + length] = compiled[start : start + length] = bytes(length)
        require(actual == compiled, "Compiled runtime mismatch: " + role)

    checks, expected = [], []

    def address(role):
        return contracts[role]["address"]

    def check(role, signature, value, argument=None):
        selector = artifact(contracts[role]["contract"])["methodIdentifiers"][signature]
        data = "0x" + selector + (argument.lower().removeprefix("0x").zfill(64) if argument else "")
        checks.append(("eth_call", [{"to": address(role), "data": data}, block_tag]))
        expected.append((role + "." + signature, int(value, 16) if isinstance(value, str) else value))

    token, core, tribunal = (settings[k].lower() for k in [
        "EURO_TOKEN_ADDRESS", "PAYMENT_INVOICE_ISSUER_ADDRESS", "TRIBUNAL_ADDRESS"
    ])
    require(core == settings["COMMUNITY_AUTHORIZER_ADDRESS"].lower(), "Core role mismatch")
    require(core != ZERO and owner != core and tribunal not in (owner, core), "Authority collision")
    for role in ["registry", "aerarium", "revenue", "fabrica", "trade", "consortiumFactory", "syndicateFactory"]:
        check(role, "owner()", owner)
    for role in ["revenue", "fabrica", "consortiumFactory", "syndicateFactory"]:
        check(role, "tribunal()", tribunal)
    for role in ["consortiumFactory", "syndicateFactory"]:
        check(role, "authorizer()", core)
    check("registry", "invoiceIssuers(address)", 1, core)
    check("registry", "invoiceIssuers(address)", 0, owner)
    for role, signature in [
        ("revenue", "revenueToken()"), ("aerarium", "revenueToken()"), ("trade", "currencyToken()"),
        ("services", "paymentToken()"), ("syndicateFactory", "paymentToken()"),
    ]:
        check(role, signature, token)
    for role in ["aerarium", "fabrica", "trade", "services", "consortiumFactory", "syndicateFactory"]:
        check(role, "revenueDistributor()", address("revenue"))
    for role in ["revenue", "aerarium"]:
        check(role, "paymentRegistry()", address("registry"))
    for role in ["revenue", "consortiumFactory"]:
        check(role, "aerarium()", address("aerarium"))
    for role in ["fabrica", "consortiumFactory"]:
        check(role, "assetImplementation()", address("assetImplementation"))
    check("consortiumFactory", "consortiumImplementation()", address("consortiumImplementation"))
    check("syndicateFactory", "syndicateImplementation()", address("syndicateImplementation"))
    for role in ["fabrica", "consortiumFactory"]:
        check("revenue", "registrars(address)", 1, address(role))
    check("revenue", "escrows(address)", 1, address("trade"))
    for role, bits in [("aerarium", 16), ("trade", 1), ("services", 2)]:
        check("revenue", "sourceRoles(address)", bits, address(role))
    check("revenue", "registrarRoles(address)", 8, address("syndicateFactory"))
    for role in ["fabrica", "trade", "consortiumFactory", "syndicateFactory"]:
        checks.append(("eth_getStorageAt", [address(role), IMPLEMENTATION_SLOT, block_tag]))
        expected.append((role + ".implementation", int(address(role + "Implementation"), 16)))
        contracts[role]["implementation"] = address(role + "Implementation")
    checks.append(("eth_call", [{"to": token, "data": "0x313ce567"}, block_tag]))
    expected.append(("token.decimals", int(settings["EURO_TOKEN_DECIMALS"])))
    for result, (label, value) in zip(rpc_batch(checks), expected):
        require(int(result, 16) == value, "Binding mismatch: " + label)

    # Export only after every receipt, runtime and binding check has succeeded.
    manifest = {
        "chainId": chain,
        "sourceRevision": broadcast["commit"],
        "verifiedAtBlock": int(block_tag, 16),
        "verifiedAtBlockHash": headers_by_number[block_tag]["hash"],
        "euroToken": token,
        "euroTokenDecimals": int(settings["EURO_TOKEN_DECIMALS"]),
        "coreSigner": core,
        "tribunal": tribunal,
        "contracts": contracts,
        "transactions": [{
            "hash": receipt["transactionHash"], "blockNumber": int(receipt["blockNumber"], 16),
            "blockHash": receipt["blockHash"], "status": 1, "gasUsed": str(int(receipt["gasUsed"], 16)),
        } for receipt in receipts],
        "verification": {"successfulReceipts": len(receipts), "compiledRuntimes": len(codes), "bindings": len(checks)},
    }
    (output / "abi").mkdir(parents=True, exist_ok=True)
    for name in {name for _, name, _ in inventory}:
        (output / "abi" / (name + ".json")).write_text(json.dumps(artifact(name)["abi"], indent=2) + "\n")
    (output / "deployment.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Verified {len(receipts)} receipts, {len(codes)} compiled runtimes and {len(checks)} bindings.")
    print("Public deployment registry and ABIs exported to", output)


if __name__ == "__main__":
    main()
