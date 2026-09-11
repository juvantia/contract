#!/usr/bin/env bash
set -euo pipefail
: "${LEASE_TAX_BPS:?Set LEASE_TAX_BPS to the configured technopark lease tax}"
forge script script/DeployJuvantia.s.sol:DeployJuvantia --rpc-url chiado --account juvantia_admin --broadcast "$@"
