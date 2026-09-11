// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Secondary ledger notified before a registered asset's economic ownership changes.
/// @dev Includes marketplace custody reassignment, not just ERC-20 transfers.
interface IAssetCheckpointObserver {
    function shareToken() external view returns (address);
    function revenueDistributor() external view returns (address);
    function checkpointAccount(address account) external;
}
