// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAssetCheckpointObserver} from "./interfaces/IAssetCheckpointObserver.sol";
import {JuvantiaAerarium} from "./JuvantiaAerarium.sol";

interface IRevenueAsset is IERC20 {
    function revenueDistributor() external view returns (address);
}

/// @notice On-chain accrual and payment settlement for registered fixed-supply assets; no backend claim signatures.
contract JuvantiaRevenueDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e36;
    IERC20 public immutable revenueToken;
    JuvantiaAerarium public aerarium;

    mapping(address => bool) public registrars;
    mapping(address => bool) public registeredAssets;
    mapping(address => uint256) public cumulativeIndex;
    mapping(address => mapping(address => uint256)) public claimedIndex;
    mapping(address => mapping(address => uint256)) public accrued;
    mapping(address => mapping(address => uint256)) public remainder;
    mapping(address => uint256) public totalDistributed;
    mapping(address => uint256) public totalClaimed;
    mapping(address => bool) public escrows;
    mapping(address => mapping(address => uint256)) public escrowedFor;
    mapping(address => mapping(address => uint256)) public escrowedBalance;
    mapping(address => mapping(address => mapping(address => uint256))) public escrowPositions;
    mapping(address => address) public checkpointObservers;

    mapping(address => mapping(bytes32 => bool)) public paid;

    event RegistrarSet(address indexed registrar, bool allowed);
    event AssetRegistered(address indexed asset);
    event CheckpointObserverRegistered(address indexed asset, address indexed observer);
    event EscrowSet(address indexed escrow, bool allowed);
    event EscrowPositionChanged(address indexed asset, address indexed escrow, address indexed holder, uint256 amount, bool deposited);
    event RevenueDistributed(address indexed assetToken, address indexed source, uint256 amount, uint256 cumulativeIndex);
    event RevenueClaimed(address indexed assetToken, address indexed account, uint256 amount);
    event AerariumSet(address indexed aerarium);
    event PaymentProcessed(bytes32 indexed paymentId, address indexed payer, address indexed assetToken, bytes32 categoryId, uint256 amount, uint256 tax, uint256 net);

    constructor(address token, address admin, address treasury) Ownable(admin) {
        require(token.code.length > 0, "Invalid token");
        revenueToken = IERC20(token);
        if (treasury != address(0)) {
            require(address(JuvantiaAerarium(treasury).revenueToken()) == token, "Treasury token mismatch");
            aerarium = JuvantiaAerarium(treasury);
        }
    }

    function setAerarium(address treasury) external onlyOwner {
        if (treasury != address(0)) {
            require(address(JuvantiaAerarium(treasury).revenueToken()) == address(revenueToken), "Treasury token mismatch");
        }
        aerarium = JuvantiaAerarium(treasury);
        emit AerariumSet(treasury);
    }

    function setRegistrar(address registrar, bool allowed) external onlyOwner {
        require(registrar != address(0), "Invalid registrar");
        registrars[registrar] = allowed;
        emit RegistrarSet(registrar, allowed);
    }

    function registerAsset(address asset) external {
        _registerAsset(asset, address(0));
    }

    /// @notice A factory may bind a treasury ledger once, atomically with asset registration.
    function registerAsset(address asset, address observer) external {
        require(observer.code.length > 0, "Invalid observer");
        require(IAssetCheckpointObserver(observer).shareToken() == asset, "Observer asset mismatch");
        require(IAssetCheckpointObserver(observer).revenueDistributor() == address(this), "Observer distributor mismatch");
        _registerAsset(asset, observer);
    }

    function _registerAsset(address asset, address observer) internal {
        require(registrars[msg.sender], "Not registrar");
        require(!registeredAssets[asset], "Already registered");
        require(IRevenueAsset(asset).revenueDistributor() == address(this), "Missing transfer hook");
        require(IERC20(asset).totalSupply() == 100_000 ether, "Invalid supply");
        registeredAssets[asset] = true;
        checkpointObservers[asset] = observer;
        emit AssetRegistered(asset);
        if (observer != address(0)) emit CheckpointObserverRegistered(asset, observer);
    }

    function setEscrow(address escrow, bool allowed) external onlyOwner {
        require(escrow.code.length > 0, "Invalid escrow");
        escrows[escrow] = allowed;
        emit EscrowSet(escrow, allowed);
    }

    /// @notice Escrowed shares accrue to their seller until sold, rather than to the marketplace.
    function effectiveBalanceOf(address asset, address account) public view returns (uint256) {
        return IERC20(asset).balanceOf(account) + escrowedFor[asset][account] - escrowedBalance[asset][account];
    }

    /// @dev Trusted escrow calls after it receives shares; exact physical custody is enforced.
    function escrowDeposit(address asset, address holder, uint256 amount) external {
        require(escrows[msg.sender] && registeredAssets[asset], "Invalid escrow asset");
        require(holder != address(0) && holder != msg.sender && amount > 0, "Invalid position");
        _checkpoint(asset, holder);
        _checkpoint(asset, msg.sender);
        escrowedBalance[asset][msg.sender] += amount;
        require(escrowedBalance[asset][msg.sender] <= IERC20(asset).balanceOf(msg.sender), "Insufficient custody");
        escrowedFor[asset][holder] += amount;
        escrowPositions[asset][msg.sender][holder] += amount;
        emit EscrowPositionChanged(asset, msg.sender, holder, amount, true);
    }

    /// @dev Withdrawals remain available after sponsorship/registration is revoked.
    function escrowWithdraw(address asset, address holder, uint256 amount) external {
        require(amount > 0 && escrowPositions[asset][msg.sender][holder] >= amount, "Invalid position");
        _checkpoint(asset, holder);
        _checkpoint(asset, msg.sender);
        escrowPositions[asset][msg.sender][holder] -= amount;
        escrowedFor[asset][holder] -= amount;
        escrowedBalance[asset][msg.sender] -= amount;
        emit EscrowPositionChanged(asset, msg.sender, holder, amount, false);
    }

    function _distribute(address asset, uint256 amount, address source) internal {
        uint256 increment = Math.mulDiv(amount, PRECISION, IERC20(asset).totalSupply());
        require(increment > 0, "Amount too small");
        cumulativeIndex[asset] += increment;
        totalDistributed[asset] += amount;
        emit RevenueDistributed(asset, source, amount, cumulativeIndex[asset]);
    }

    /// @notice Direct zero-tax distribution of external revenue to asset shareholders.
    function distributeRevenue(address asset, uint256 amount) external nonReentrant {
        require(registeredAssets[asset], "Unknown asset");
        require(amount > 0, "Zero amount");
        uint256 beforeBalance = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        require(revenueToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");
        _distribute(asset, amount, msg.sender);
    }

    /// @notice Universal payment processing: collects gross amount, deducts city tax to Aerarium, distributes net to shareholders, and emits receipt.
    function processPayment(
        address asset,
        uint256 amount,
        bytes32 categoryId,
        bytes32 paymentId
    ) external nonReentrant {
        require(registeredAssets[asset], "Unknown asset");
        require(paymentId != bytes32(0) && amount > 0, "Invalid payment");
        require(!paid[msg.sender][paymentId], "Already paid");
        paid[msg.sender][paymentId] = true;

        uint256 beforeBalance = revenueToken.balanceOf(address(this));
        revenueToken.safeTransferFrom(msg.sender, address(this), amount);
        require(revenueToken.balanceOf(address(this)) - beforeBalance == amount, "Incorrect deposit");

        uint256 tax = 0;
        if (address(aerarium) != address(0) && categoryId != bytes32(0)) {
            uint256 taxRate = aerarium.getTaxRateBps(categoryId);
            tax = Math.mulDiv(amount, taxRate, 10_000);
        }
        uint256 net = amount - tax;

        if (tax > 0) {
            revenueToken.forceApprove(address(aerarium), tax);
            aerarium.receiveTax(tax, categoryId);
        }

        if (net > 0) {
            _distribute(asset, net, msg.sender);
        }

        emit PaymentProcessed(paymentId, msg.sender, asset, categoryId, amount, tax, net);
    }

    /// @dev Called by the registered share token BEFORE balances change. Never sends funds.
    function checkpointTransfer(address from, address to) external {
        require(registeredAssets[msg.sender], "Unknown asset");
        if (from != address(0)) _checkpoint(msg.sender, from);
        if (to != address(0) && to != from) _checkpoint(msg.sender, to);
    }

    function claimable(address asset, address account) public view returns (uint256) {
        uint256 delta = cumulativeIndex[asset] - claimedIndex[asset][account];
        uint256 balance = effectiveBalanceOf(asset, account);
        return accrued[asset][account] + Math.mulDiv(balance, delta, PRECISION)
            + (mulmod(balance, delta, PRECISION) + remainder[asset][account]) / PRECISION;
    }

    function _checkpoint(address asset, address account) internal {
        // Independent treasury distributions can change even if this ledger's index did not.
        address observer = checkpointObservers[asset];
        if (observer != address(0)) IAssetCheckpointObserver(observer).checkpointAccount(account);
        uint256 index = cumulativeIndex[asset];
        uint256 delta = index - claimedIndex[asset][account];
        if (delta == 0) return;
        uint256 balance = effectiveBalanceOf(asset, account);
        uint256 fractional = mulmod(balance, delta, PRECISION) + remainder[asset][account];
        accrued[asset][account] += Math.mulDiv(balance, delta, PRECISION) + fractional / PRECISION;
        remainder[asset][account] = fractional % PRECISION;
        claimedIndex[asset][account] = index;
    }

    function claim(address asset) external nonReentrant returns (uint256) {
        return _claimFor(asset, msg.sender);
    }

    function claimFor(address asset, address account) external nonReentrant returns (uint256) {
        require(account != address(0), "Invalid account");
        return _claimFor(asset, account);
    }

    function claimBatch(address[] calldata assets) external nonReentrant returns (uint256 total) {
        for (uint256 i; i < assets.length; ++i) total += _claimFor(assets[i], msg.sender);
    }

    function _claimFor(address asset, address account) internal returns (uint256 amount) {
        require(registeredAssets[asset], "Unknown asset");
        _checkpoint(asset, account);
        amount = accrued[asset][account];
        accrued[asset][account] = 0;
        if (amount != 0) {
            totalClaimed[asset] += amount;
            revenueToken.safeTransfer(account, amount);
            emit RevenueClaimed(asset, account, amount);
        }
    }
}
