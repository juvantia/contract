#!/usr/bin/env bash
set -euo pipefail
: "${BLOCKCHAIN_CHAIN_ID:?Set BLOCKCHAIN_CHAIN_ID}"
: "${BLOCKCHAIN_RPC_URL:?Set BLOCKCHAIN_RPC_URL}"
: "${EURO_TOKEN_ADDRESS:?Set EURO_TOKEN_ADDRESS}"
: "${EURO_TOKEN_DECIMALS:?Set EURO_TOKEN_DECIMALS}"
: "${DEPLOYER_ADDRESS:?Set DEPLOYER_ADDRESS}"
: "${PAYMENT_INVOICE_ISSUER_ADDRESS:?Set PAYMENT_INVOICE_ISSUER_ADDRESS}"
: "${COMMUNITY_AUTHORIZER_ADDRESS:?Set COMMUNITY_AUTHORIZER_ADDRESS}"
: "${TRIBUNAL_ADDRESS:?Set TRIBUNAL_ADDRESS}"

# Simulation needs only the expected public sender. Load the encrypted signing account
# only for an explicitly requested broadcast.
broadcast_requested=false
for argument in "$@"; do
    if [[ "$argument" == --skip-simulation || "$argument" == --skip-simulation=* || "$argument" == --resume ]]; then
        printf '%s\n' 'Deployment simulation is required.' >&2
        exit 1
    fi
    if [[ "$argument" == --broadcast ]]; then
        broadcast_requested=true
    fi
done
wallet_arguments=(--sender "$DEPLOYER_ADDRESS")
if [[ "$broadcast_requested" == true ]]; then
    wallet_arguments=(--account "${DEPLOYER_ACCOUNT:-juvantia_admin}")
fi
forge script script/DeployJuvantia.s.sol:DeployJuvantia \
    --rpc-url "$BLOCKCHAIN_RPC_URL" "${wallet_arguments[@]}" "$@"
