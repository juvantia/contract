# Juvantia Smart Contract Deployments

This document serves as a knowledge base for all deployed smart contracts in the Juvantia project.

## Arc Testnet (Chain ID: 5042002)

**Deployment Date:** May 8, 2026
**Deployer Account:** `juvantia_admin`

### Contract Addresses

| Contract | Address | Description |
| :--- | :--- | :--- |
| **Factory Proxy** | `0x0A497d73093c80A72AbE5e748d08fA61e4Be396F` | **USE THIS IN BACKEND.** The ERC1967 Proxy pointing to the `JuvantiaAssetFabrica` logic. This is the main entry point for creating new assets. |
| **Asset Logic (Impl)** | `0xb7EEB6E2509a21a74e9670DE7180c8305Cd9E7aA` | The `JuvantiaAsset` implementation logic contract. The Factory clones this to create new assets. |
| **Factory Logic (Impl)** | `0x941a7AEF0aD54804416E74FfA4D77E87599D6602` | The `JuvantiaAssetFabrica` implementation logic contract. The Factory Proxy delegates calls here. |
| **TradeHub Proxy** | `0xc6e367b6886D7e0280c23BDC4507680882594bE2` | **USE THIS IN BACKEND.** The ERC1967 Proxy pointing to the `JuvantiaTradeHub` logic. Handles escrow-based limit orders for asset fractions. |
| **TradeHub Logic (Impl)** | `0x611a053Ef91d37eb19c8F82931B95f9b54864FD8` | The `JuvantiaTradeHub` implementation logic contract. |

### Network Info
- **RPC URL Config Name:** `arc_testnet`
- **Block Explorer:** [ArcScan](https://testnet.arcscan.app/)
- **Deployment Command Used:**
  ```bash
  forge script script/DeployJuvantia.s.sol:DeployJuvantia --rpc-url arc_testnet --account juvantia_admin --broadcast --verify --delay 10
  ```

## Base Sepolia (Chain ID: 84532)

**Deployment Date:** May 6, 2026
**Deployer Account:** `juvantia_admin`

### Contract Addresses

| Contract | Address | Description |
| :--- | :--- | :--- |
| **Factory Proxy** | `0x0A497d73093c80A72AbE5e748d08fA61e4Be396F` | **USE THIS IN BACKEND.** The ERC1967 Proxy pointing to the `JuvantiaAssetFabrica` logic. This is the main entry point for creating new assets. |
| **Asset Logic (Impl)** | `0xb7EEB6E2509a21a74e9670DE7180c8305Cd9E7aA` | The `JuvantiaAsset` implementation logic contract. The Factory clones this to create new assets. |
| **Factory Logic (Impl)** | `0x941a7AEF0aD54804416E74FfA4D77E87599D6602` | The `JuvantiaAssetFabrica` implementation logic contract. The Factory Proxy delegates calls here. |

### Network Info
- **RPC URL Config Name:** `base_sepolia`
- **Block Explorer:** [Base Sepolia Scan](https://sepolia.basescan.org/)
- **Deployment Command Used:**
  ```bash
  forge script script/DeployJuvantia.s.sol:DeployJuvantia --rpc-url base_sepolia --account juvantia_admin --broadcast --verify --delay 10
  ```
