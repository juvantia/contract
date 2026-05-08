# Juvantia Smart Contracts

[![License: MIT][license-badge]][license]

This repository serves as a public, read-only registry for the smart contracts deployed by the **Juvantia Foundation**. Our goal is to provide complete transparency regarding the code that powers our ecosystem, allowing users, auditors, and the broader community to independently verify the logic and security of our assets.

[license]: ./LICENSE
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## Overview

This repository will house the growing collection of smart contracts utilized by the Juvantia Foundation. Currently, it includes the foundational infrastructure for creating and managing Juvantia Assets.

### Core Contracts

The initial architecture utilizes a robust Factory pattern combined with Upgradeable and Minimal Proxy patterns to ensure long-term flexibility, security, and gas efficiency.

#### 1. JuvantiaAssetFabrica.sol (The Factory)
This is the primary entry point and management contract for deploying new assets within the Juvantia ecosystem. 
*   **Upgradeability**: It is deployed behind an **ERC1967 Proxy** utilizing the UUPS (Universal Upgradeable Proxy Standard) pattern. This allows the Foundation to upgrade the factory's logic in the future (e.g., to add new asset types or features) while maintaining a consistent, permanent address.
*   **Gas Efficiency**: Instead of deploying a massive new contract for every single asset, the factory utilizes the **EIP-1167 Minimal Proxy (Clones)** standard. It deploys lightweight "clones" that point to a single master implementation of the asset logic.
*   **Access Control**: Only authorized administrators of the Juvantia Foundation can trigger the creation of new assets, ensuring strict control over token generation.

#### 2. JuvantiaAsset.sol (The Asset Logic)
This contract contains the core logic, rules, and behaviors for the individual assets created by the factory. 
*   **Standard Compliance**: It inherits from audited OpenZeppelin standards, functioning as a secure ERC20 token.
*   **Initialization**: Because it is deployed as a clone, it relies on an `initialize()` function rather than a standard constructor to set its initial state (name, symbol, and initial supply).
*   **Minting & Burning**: The contract includes administrative controls allowing the Foundation to manage the supply strictly according to the platform's economic design. Upon creation, a predefined initial supply is minted directly to the designated owner.

## Verification

All contracts deployed by the Juvantia Foundation are verified on block explorers. You can compare the source code found in this repository directly with the code running on the blockchain to ensure absolute parity.
