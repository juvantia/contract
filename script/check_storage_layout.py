#!/usr/bin/env python3
"""Check append-only infrastructure storage and pinned namespaced-storage dependencies."""

import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "storage-layout/infrastructure-v1.json"
CONTRACTS = ("JuvantiaRevenueDistributor", "JuvantiaAerarium", "JuvantiaPaymentRegistry")
DEPENDENCIES = ("lib/openzeppelin-contracts", "lib/openzeppelin-contracts-upgradeable")


def normalize(layout):
    def shape(type_id):
        item = layout["types"][type_id]
        result = {"label": item["label"], "encoding": item["encoding"], "bytes": int(item["numberOfBytes"])}
        for field in ("key", "value", "base"):
            if field in item:
                result[field] = shape(item[field])
        if "members" in item:
            result["members"] = [entry(member) for member in item["members"]]
        return result

    def entry(item):
        return {"label": item["label"], "slot": str(item["slot"]), "offset": item["offset"],
                "type": shape(item["type"])}

    return [entry(item) for item in layout["storage"]]


def compatible(previous, current):
    if previous["dependencies"] != current["dependencies"]:
        raise RuntimeError("Pinned OpenZeppelin dependencies changed; review namespaced storage before updating the baseline")
    for contract, stored in previous["contracts"].items():
        actual = current["contracts"].get(contract, [])
        if len(actual) < len(stored):
            raise RuntimeError("Existing storage removed: " + contract)
        for before, after in zip(stored, actual):
            if before != after:
                raise RuntimeError("Incompatible storage: " + contract + "." + before["label"])


def snapshot(candidates=None):
    candidates = candidates or {}
    dependencies = {}
    for relative in DEPENDENCIES:
        directory = ROOT / relative
        if subprocess.check_output(["git", "status", "--porcelain"], cwd=directory, text=True).strip():
            raise RuntimeError("Modified OpenZeppelin dependency: " + relative)
        dependencies[relative] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=directory, text=True).strip()
    contracts = {}
    for contract in CONTRACTS:
        result = subprocess.run(["forge", "inspect", candidates.get(contract, contract), "storage-layout", "--json"],
                                cwd=ROOT, capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise RuntimeError("Storage compilation failed: " + contract)
        contracts[contract] = normalize(json.loads(result.stdout))
    return {"schemaVersion": 1, "dependencies": dependencies, "contracts": contracts}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", action="store_true", help="Create or extend the baseline after checking existing fields")
    parser.add_argument("--candidate", action="append", default=[], metavar="CONTRACT=SOURCE:IMPLEMENTATION",
                        help="Validate a separately named proposed implementation against its canonical contract")
    args = parser.parse_args()
    candidates = {}
    for value in args.candidate:
        contract, separator, target = value.partition("=")
        if contract not in CONTRACTS or not separator or not target or target.startswith("-"):
            parser.error("Candidate must map a canonical infrastructure contract to its implementation")
        if contract in candidates:
            parser.error("Duplicate candidate: " + contract)
        candidates[contract] = target
    current = snapshot(candidates)
    if BASELINE.exists():
        compatible(json.loads(BASELINE.read_text()), current)
    elif not args.record:
        raise RuntimeError("No reviewed infrastructure storage baseline")
    if args.record:
        BASELINE.parent.mkdir(parents=True, exist_ok=True)
        BASELINE.write_text(json.dumps(current, indent=2) + "\n")
    print("Infrastructure storage is append-only; OpenZeppelin namespaced-storage dependencies match.")


if __name__ == "__main__":
    main()
