// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice A governed treasury bound once to its registered ownership token.
interface IRevenueTreasury {
    function shareToken() external view returns (address);
    function revenueDistributor() external view returns (address);
}
