#!/usr/bin/env python3
"""Publish existing contracts' sources to Blockscout, without a wallet or transactions."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import time
import urllib.request
import urllib.error
import uuid


ROOT = Path(__file__).resolve().parents[1]
USER_AGENT = "juvantia-contract-release/1.0 (+https://github.com/juvantia/contract)"


def request_json(url, data=None, content_type=None):
    headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    if content_type:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(url, data=data, headers=headers)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code not in [403, 429, 500, 502, 503, 504] or attempt == 3:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(3 * (attempt + 1))


def multipart(fields, files):
    boundary = "juvantia-" + uuid.uuid4().hex
    parts = []
    for key, value in fields.items():
        parts.append(("--" + boundary + '\r\nContent-Disposition: form-data; name="' + key
                      + '"\r\n\r\n' + value + "\r\n").encode())
    for index, (filename, content, mime_type) in enumerate(files):
        parts.append(("--" + boundary + '\r\nContent-Disposition: form-data; name="files[' + str(index)
                      + ']"; filename="' + filename + '"\r\nContent-Type: ' + mime_type + '\r\n\r\n').encode()
                     + content + b"\r\n")
    parts.append(("--" + boundary + "--\r\n").encode())
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("broadcast", type=Path)
    parser.add_argument("explorer", help="Public Blockscout instance URL")
    parser.add_argument("--solc", type=Path, help="Installed Solidity compiler executable")
    parser.add_argument("--method", choices=["sourcify", "standard-input"], default="sourcify")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    broadcast = json.loads(args.broadcast.read_text())
    if manifest["chainId"] != broadcast["chain"] or broadcast["pending"]:
        raise RuntimeError("Chain mismatch or incomplete broadcast")
    transactions = {tx["contractAddress"].lower(): tx for tx in broadcast["transactions"]
                    if tx["transactionType"] == "CREATE"}
    jobs = []
    compiled_inputs = {}
    for role, record in manifest["contracts"].items():
        tx = transactions[record["address"].lower()]
        if tx["hash"].lower() != record["transactionHash"].lower():
            raise RuntimeError("Creation transaction mismatch: " + role)
        name = tx["contractName"]
        artifact = json.loads((ROOT / "out" / (name + ".sol") / (name + ".json")).read_text())
        bytecode = artifact["bytecode"]["object"].removeprefix("0x").lower()
        creation = tx["transaction"]["input"].removeprefix("0x").lower()
        if not bytecode or not creation.startswith(bytecode):
            raise RuntimeError("Creation bytecode differs from local build: " + role)
        target = artifact["metadata"]["settings"]["compilationTarget"]
        if len(target) != 1 or next(iter(target.values())) != name:
            raise RuntimeError("Compilation target mismatch: " + role)
        version = artifact["metadata"]["compiler"]["version"]
        compiler = "v" + version
        if name not in compiled_inputs:
            # Preserve original context remappings, including absolute prefixes in metadata.
            # Forge's verification-input normalization can change the metadata/bytecode hash.
            settings = copy.deepcopy(artifact["metadata"]["settings"])
            settings.pop("compilationTarget")
            settings["outputSelection"] = {"*": {"*": ["abi", "evm.bytecode", "evm.deployedBytecode", "metadata"]}}
            standard_input = {"language": "Solidity", "settings": settings, "sources": {
                path: {"content": (ROOT / path).read_text()} for path in artifact["metadata"]["sources"]
            }}
            semver = version.split("+")[0]
            candidates = [args.solc, Path.home() / ".local/share/svm" / semver / ("solc-" + semver),
                          Path.home() / ".svm" / semver / ("solc-" + semver), shutil.which("solc")]
            executable = next((str(path) for path in candidates if path and Path(path).is_file()), None)
            if not executable:
                raise RuntimeError("Provide the installed compiler with --solc")
            result = subprocess.run([executable, "--standard-json"], input=json.dumps(standard_input),
                                    cwd=ROOT, capture_output=True, text=True, timeout=90)
            output = json.loads(result.stdout)
            if result.returncode or any(e["severity"] == "error" for e in output.get("errors", [])):
                raise RuntimeError("Local source compilation failed: " + role)
            compiled = output["contracts"][next(iter(target))][name]["evm"]["bytecode"]["object"]
            if compiled.lower() != bytecode:
                raise RuntimeError("Recompiled source differs from deployment creation bytecode: " + role)
            compiled_inputs[name] = standard_input
        standard_input = compiled_inputs[name]
        digest = hashlib.sha256(json.dumps({"explorer": args.explorer.rstrip("/"), "method": args.method,
                                            "input": standard_input}, sort_keys=True).encode()).hexdigest()
        constructor = creation[len(bytecode):]
        jobs.append((role, name, record["address"], standard_input, compiler, constructor,
                     record["transactionHash"], digest, artifact["metadata"]))

    # Every creation payload is checked before the first public source submission.
    logs = Path("/tmp/juvantia-explorer-verification")
    logs.mkdir(mode=0o700, exist_ok=True)
    os.chmod(logs, 0o700)
    base = args.explorer.rstrip("/")
    print("Exact original creation bytecode reproduced for every publication target.", flush=True)
    for role, name, address, standard_input, compiler, constructor, transaction, digest, metadata in jobs:
        info = request_json(base + "/api/v2/addresses/" + address)
        if info.get("is_verified") and info.get("name") == name:
            print("Already verified: " + role, flush=True)
            continue
        submitted = logs / (role + "-submitted.json")
        previous = json.loads(submitted.read_text()) if submitted.exists() else {}
        if previous.get("transactionHash") == transaction and previous.get("inputSha256") == digest:
            print("Awaiting accepted submission: " + role, flush=True)
            continue
        if args.method == "sourcify":
            fields = {}
            files = [("metadata.json", json.dumps(metadata).encode(), "application/json")]
            files.extend((path, source["content"].encode(), "text/plain")
                         for path, source in standard_input["sources"].items())
        else:
            fields = {"compiler_version": compiler, "contract_name": name,
                      "autodetect_constructor_args": "false", "constructor_args": constructor, "license_type": "mit"}
            files = [("input.json", json.dumps(standard_input).encode(), "application/json")]
        body, content_type = multipart(fields, files)
        response = request_json(base + "/api/v2/smart-contracts/" + address + "/verification/via/" + args.method,
                                body, content_type)
        if response.get("message") != "Smart-contract verification started":
            raise RuntimeError("Explorer did not accept source submission: " + role)
        fd = os.open(submitted, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w") as handle:
            json.dump({"transactionHash": transaction, "inputSha256": digest, "accepted": True}, handle)
        print("Source submission accepted: " + role, flush=True)
        time.sleep(1)

    records = {}
    for role, name, address, *_ in jobs:
        info = None
        for attempt in range(12):
            try:
                info = request_json(base + "/api/v2/addresses/" + address)
                if info.get("is_verified") and info.get("name") == name:
                    break
            except Exception:
                info = None
            if attempt < 11:
                time.sleep(5)
        if not info or not info.get("is_verified") or info.get("name") != name:
            raise RuntimeError("Explorer did not confirm verified source/name: " + role)
        canonical = manifest["contracts"][role]
        if canonical.get("implementation"):
            implementations = info.get("implementations") or []
            expected = canonical["implementation"].lower()
            if info.get("proxy_type") != "eip1967" or not any(
                item.get("address_hash", "").lower() == expected and item.get("name") == canonical["contract"]
                for item in implementations
            ):
                raise RuntimeError("Explorer proxy implementation/name mismatch: " + role)
        records[role] = {"address": address, "isVerified": True, "name": info["name"],
                         "url": args.explorer.rstrip("/") + "/address/" + address + "?tab=contract",
                         "proxyType": info.get("proxy_type"),
                         "implementations": info.get("implementations") or []}
        print("Explorer verified name/source: " + role, flush=True)
    output = {"chainId": manifest["chainId"], "explorer": args.explorer.rstrip("/"), "method": args.method,
              "verifiedAt": datetime.now(timezone.utc).isoformat(),
              "sourceRevision": manifest["sourceRevision"], "contracts": records}
    (args.manifest.parent / "explorer-verification.json").write_text(json.dumps(output, indent=2) + "\n")
    print("Explorer confirmed verified source and name for all " + str(len(records)) + " contracts.", flush=True)


if __name__ == "__main__":
    main()
