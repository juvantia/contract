#!/usr/bin/env bash
set -euo pipefail
: "${BLOCKCHAIN_CHAIN_ID:?Set BLOCKCHAIN_CHAIN_ID}"
: "${BLOCKCHAIN_RPC_URL:?Set BLOCKCHAIN_RPC_URL}"
: "${EURO_TOKEN_ADDRESS:?Set EURO_TOKEN_ADDRESS}"
forge script script/DeployJuvantia.s.sol:DeployJuvantia --rpc-url "$BLOCKCHAIN_RPC_URL" --account juvantia_admin --broadcast "$@"
