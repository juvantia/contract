#!/usr/bin/env bash
set -euo pipefail
: "${LEASE_TAX_BPS:?Set LEASE_TAX_BPS to the configured technopark lease tax}"
: "${BLOCKCHAIN_CHAIN_ID:?Set BLOCKCHAIN_CHAIN_ID}"
: "${BLOCKCHAIN_RPC_URL:?Set BLOCKCHAIN_RPC_URL}"
: "${EURO_TOKEN_ADDRESS:?Set EURO_TOKEN_ADDRESS}"
forge script script/DeployJuvantia.s.sol:DeployJuvantia --rpc-url "$BLOCKCHAIN_RPC_URL" --account juvantia_admin --broadcast "$@"
