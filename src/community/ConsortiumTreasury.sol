// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {JuvantiaRevenueDistributor} from "../JuvantiaRevenueDistributor.sol";

/// @notice Consortium operating treasury and governed funding of owners' revenue earnings.
/// @dev Governance belongs in Consortium: allocation/spending/revenue gateways are INTERNAL.
/// This base cannot be deployed as a functioning company or used to bypass a shareholder vote.
abstract contract ConsortiumTreasury is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;
    IERC20 public shareToken;
    JuvantiaRevenueDistributor public revenueDistributor;
    uint256 public totalAllocated;

    event OperatingDeposit(address indexed payer, bytes32 indexed referenceId, uint256 amount);
    event OperatingSpent(address indexed recipient, bytes32 indexed referenceId, uint256 amount);
    event DeviceRevenueReceived(address indexed assetToken, uint256 amount);
    event DistributableAllocated(uint256 amount, uint256 circulatingSupply, uint256 cumulativeIndex);

    constructor() {
        _disableInitializers();
    }

    function _initializeTreasury(address token, address shares, address distributor) internal onlyInitializing {
        require(
            token.code.length > 0 && shares.code.length > 0 && distributor.code.length > 0,
            "Invalid treasury configuration"
        );
        require(token != shares, "Invalid share token");
        require(address(JuvantiaRevenueDistributor(distributor).revenueToken()) == token, "Payment token mismatch");
        paymentToken = IERC20(token);
        shareToken = IERC20(shares);
        revenueDistributor = JuvantiaRevenueDistributor(distributor);
    }

    /// @notice Every incoming euro-token unit belongs to operations unless expressly allocated.
    /// @dev ERC-20 transfers have no receiver hook. Derivation makes even unsolicited direct
    /// payments/claimFor receipts immediately available, without a keeper, sync call or indexer.
    function operatingBalance() public view returns (uint256) {
        return paymentToken.balanceOf(address(this));
    }

    /// @notice The second account is reserved in RevenueDistributor, outside operating custody.
    function distributablePool() public view returns (uint256) {
        return revenueDistributor.totalDistributed(address(shareToken)) - totalClaimed();
    }

    function totalClaimed() public view returns (uint256) {
        return revenueDistributor.totalClaimed(address(shareToken));
    }

    function cumulativeIndex() public view returns (uint256) {
        return revenueDistributor.cumulativeIndex(address(shareToken));
    }

    function treasuryShares() public view returns (uint256) {
        return revenueDistributor.effectiveBalanceOf(address(shareToken), address(this));
    }

    function circulatingSupply() public view returns (uint256) {
        return shareToken.totalSupply() - treasuryShares();
    }

    function depositOperating(uint256 amount, bytes32 referenceId) external nonReentrant {
        require(amount > 0, "Zero amount");
        uint256 beforeBalance = paymentToken.balanceOf(address(this));
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        require(paymentToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");
        emit OperatingDeposit(msg.sender, referenceId, amount);
    }

    /// @notice Compatibility view; owners receive all earnings directly from RevenueDistributor.
    function claimable(address account) public view returns (uint256) {
        return revenueDistributor.claimable(address(shareToken), account);
    }

    /// @dev Must only be called by an approved revenue-distribution proposal.
    function _allocateDistributable(uint256 amount) internal {
        require(
            revenueDistributor.revenueTreasuries(address(shareToken)) == address(this), "Unregistered revenue treasury"
        );
        require(amount > 0 && amount <= operatingBalance(), "Insufficient operating funds");
        uint256 supply = circulatingSupply();
        require(supply > 0, "No circulating shares");
        paymentToken.forceApprove(address(revenueDistributor), amount);
        revenueDistributor.distributeRevenue(address(shareToken), amount);
        totalAllocated += amount;
        emit DistributableAllocated(amount, supply, cumulativeIndex());
    }

    /// @dev Must only be called by authorized Magister spending/governance paths.
    function _spendOperating(address recipient, uint256 amount, bytes32 referenceId) internal {
        require(recipient != address(0) && recipient != address(this), "Invalid recipient");
        require(amount > 0 && amount <= operatingBalance(), "Insufficient operating funds");
        paymentToken.safeTransfer(recipient, amount);
        emit OperatingSpent(recipient, referenceId, amount);
    }

    /// @dev Must only be exposed through the Magister gateway in Consortium.
    function _claimDeviceRevenue(address asset) internal returns (uint256 amount) {
        uint256 beforeBalance = paymentToken.balanceOf(address(this));
        revenueDistributor.claim(asset);
        amount = paymentToken.balanceOf(address(this)) - beforeBalance;
        require(amount > 0, "No revenue claimed");
        emit DeviceRevenueReceived(asset, amount);
    }
}
