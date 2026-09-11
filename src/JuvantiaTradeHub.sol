// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {JuvantiaRevenueDistributor} from "./JuvantiaRevenueDistributor.sol";

contract JuvantiaTradeHub is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public currencyToken;
    JuvantiaRevenueDistributor public revenueDistributor;

    struct Order {
        address seller;
        address assetToken;
        uint256 amountRemaining;
        uint256 pricePerToken; // Price in currencyToken per 10**18 units of assetToken
        bool isActive;
    }

    mapping(uint256 => Order) public orders;
    uint256 public nextOrderId;

    mapping(address => uint256) public pendingWithdrawals;

    event OrderCreated(uint256 indexed orderId, address indexed seller, address indexed assetToken, uint256 amount, uint256 pricePerToken);
    event OrderFilled(uint256 indexed orderId, address indexed buyer, uint256 amount, uint256 totalCost);
    event OrderCancelled(uint256 indexed orderId);
    event Withdrawal(address indexed seller, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _currencyToken, address initialOwner, address distributor) initializer public {
        __Ownable_init(initialOwner);

        require(_currencyToken != address(0), "Invalid currency token");
        currencyToken = IERC20(_currencyToken);
        require(address(JuvantiaRevenueDistributor(distributor).revenueToken()) == _currencyToken, "Token mismatch");
        revenueDistributor = JuvantiaRevenueDistributor(distributor);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Create an order to sell `amount` of `assetToken`.
     * @param assetToken The address of the asset being sold.
     * @param amount The total number of asset tokens (e.g., 1000 * 10**18).
     * @param pricePerToken The price in currencyToken for ONE full asset token (i.e. 10**18 wei).
     */
    function createOrder(address assetToken, uint256 amount, uint256 pricePerToken) external nonReentrant returns (uint256) {
        require(amount > 0, "Amount must be > 0");
        require(pricePerToken > 0, "Price must be > 0");
        require(assetToken != address(0), "Invalid asset token");
        require(revenueDistributor.registeredAssets(assetToken), "Unknown asset");

        // Transfer asset tokens from seller to JuvantiaTradeHub (requires prior approval)
        IERC20(assetToken).safeTransferFrom(msg.sender, address(this), amount);
        revenueDistributor.escrowDeposit(assetToken, msg.sender, amount);

        uint256 orderId = nextOrderId++;
        orders[orderId] = Order({
            seller: msg.sender,
            assetToken: assetToken,
            amountRemaining: amount,
            pricePerToken: pricePerToken,
            isActive: true
        });

        emit OrderCreated(orderId, msg.sender, assetToken, amount, pricePerToken);
        return orderId;
    }

    /**
     * @dev Buy a specific `amount` from an order.
     */
    function fillOrder(uint256 orderId, uint256 amount) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.isActive, "Order inactive");
        require(amount > 0 && amount <= order.amountRemaining, "Invalid amount");

        // EURe base units per full share. Round up so splitting fills cannot underpay.
        uint256 totalCost = Math.mulDiv(amount, order.pricePerToken, 1e18, Math.Rounding.Ceil);
        require(totalCost > 0, "Total cost too small");

        order.amountRemaining -= amount;
        if (order.amountRemaining == 0) {
            order.isActive = false;
        }

        // Transfer currency from buyer to JuvantiaTradeHub (requires prior approval)
        currencyToken.safeTransferFrom(msg.sender, address(this), totalCost);
        
        // Credit the seller's internal balance
        pendingWithdrawals[order.seller] += totalCost;
        
        // Transfer asset tokens to buyer
        revenueDistributor.escrowWithdraw(order.assetToken, order.seller, amount);
        IERC20(order.assetToken).safeTransfer(msg.sender, amount);

        emit OrderFilled(orderId, msg.sender, amount, totalCost);
    }

    /**
     * @dev Seller cancels their active order and reclaims unsold tokens.
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage order = orders[orderId];
        require(order.isActive, "Order inactive");
        require(order.seller == msg.sender, "Not the seller");

        uint256 amountToReturn = order.amountRemaining;
        order.amountRemaining = 0;
        order.isActive = false;

        // Return remaining asset tokens to the seller
        revenueDistributor.escrowWithdraw(order.assetToken, order.seller, amountToReturn);
        IERC20(order.assetToken).safeTransfer(msg.sender, amountToReturn);

        emit OrderCancelled(orderId);
    }

    /**
     * @dev Sellers withdraw their accumulated currency.
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        
        // Transfer accumulated currency to the seller
        currencyToken.safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);
    }
}
