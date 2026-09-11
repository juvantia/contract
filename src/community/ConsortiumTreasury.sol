// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {JuvantiaRevenueDistributor} from "../JuvantiaRevenueDistributor.sol";

/// @notice Consortium's segregated treasury and transfer-aware dividend accounting.
/// @dev Governance belongs in Consortium: allocation/spending/revenue gateways are INTERNAL.
/// This base cannot be deployed as a functioning company or used to bypass a shareholder vote.
abstract contract ConsortiumTreasury is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DIVIDEND_PRECISION = 1e36;
    IERC20 public paymentToken;
    IERC20 public shareToken;
    JuvantiaRevenueDistributor public revenueDistributor;
    uint256 public distributablePool;
    uint256 public cumulativeIndex;
    uint256 public totalAllocated;
    uint256 public totalClaimed;
    mapping(address => uint256) public claimedIndex;
    mapping(address => uint256) public accrued;
    mapping(address => uint256) public remainder;

    event OperatingDeposit(address indexed payer, bytes32 indexed referenceId, uint256 amount);
    event OperatingSpent(address indexed recipient, bytes32 indexed referenceId, uint256 amount);
    event DeviceRevenueReceived(address indexed assetToken, uint256 amount);
    event DistributableAllocated(uint256 amount, uint256 circulatingSupply, uint256 cumulativeIndex);
    event RevenueClaimed(address indexed shareholder, uint256 amount);

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
        return paymentToken.balanceOf(address(this)) - distributablePool;
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

    /// @dev Called for transfers AND changes to attributed marketplace custody.
    function checkpointAccount(address account) external {
        require(msg.sender == address(revenueDistributor), "Not distributor");
        _checkpointDividend(account);
    }

    function claimable(address account) public view returns (uint256) {
        if (account == address(this) || account == address(0)) return 0;
        uint256 delta = cumulativeIndex - claimedIndex[account];
        uint256 balance = revenueDistributor.effectiveBalanceOf(address(shareToken), account);
        return accrued[account] + Math.mulDiv(balance, delta, DIVIDEND_PRECISION)
            + (mulmod(balance, delta, DIVIDEND_PRECISION) + remainder[account]) / DIVIDEND_PRECISION;
    }

    function _checkpointDividend(address account) internal {
        if (account == address(0)) return;
        uint256 index = cumulativeIndex;
        uint256 delta = index - claimedIndex[account];
        if (delta == 0) return;
        if (account != address(this)) {
            uint256 balance = revenueDistributor.effectiveBalanceOf(address(shareToken), account);
            uint256 fractional = mulmod(balance, delta, DIVIDEND_PRECISION) + remainder[account];
            accrued[account] += Math.mulDiv(balance, delta, DIVIDEND_PRECISION) + fractional / DIVIDEND_PRECISION;
            remainder[account] = fractional % DIVIDEND_PRECISION;
        }
        claimedIndex[account] = index;
    }

    function claim() external nonReentrant returns (uint256) {
        return _claimFor(msg.sender);
    }

    /// @notice Anyone may trigger a claim; payment always goes to its actual beneficiary.
    function claimFor(address shareholder) external nonReentrant returns (uint256) {
        require(shareholder != address(0) && shareholder != address(this), "Invalid shareholder");
        return _claimFor(shareholder);
    }

    function _claimFor(address shareholder) internal returns (uint256 amount) {
        _checkpointDividend(shareholder);
        amount = accrued[shareholder];
        accrued[shareholder] = 0;
        if (amount != 0) {
            distributablePool -= amount;
            totalClaimed += amount;
            paymentToken.safeTransfer(shareholder, amount);
            emit RevenueClaimed(shareholder, amount);
        }
    }

    /// @dev Must only be called by an approved revenue-distribution proposal.
    function _allocateDistributable(uint256 amount) internal {
        require(
            revenueDistributor.checkpointObservers(address(shareToken)) == address(this), "Missing treasury checkpoint"
        );
        require(amount > 0 && amount <= operatingBalance(), "Insufficient operating funds");
        uint256 supply = circulatingSupply();
        require(supply > 0, "No circulating shares");
        uint256 increment = Math.mulDiv(amount, DIVIDEND_PRECISION, supply);
        require(increment > 0, "Amount too small");
        distributablePool += amount;
        totalAllocated += amount;
        cumulativeIndex += increment;
        emit DistributableAllocated(amount, supply, cumulativeIndex);
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
