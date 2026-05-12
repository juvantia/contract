// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JuvantiaTradeHub.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 _decimals) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** _decimals);
    }
}

contract JuvantiaTradeHubTest is Test {
    JuvantiaTradeHub public tradeHub;
    MockERC20 public eurc;
    MockERC20 public assetToken;

    address public admin = address(1);
    address public seller = address(2);
    address public buyer = address(3);

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy Mock EURC (6 decimals typically, but we'll use 18 for simplicity here or 6, let's use 6)
        eurc = new MockERC20("Euro Coin", "EURC", 6);
        
        // Deploy Mock Asset Token (18 decimals)
        assetToken = new MockERC20("Asset Token", "AST", 18);

        // Deploy JuvantiaTradeHub
        JuvantiaTradeHub implementation = new JuvantiaTradeHub();
        bytes memory data = abi.encodeWithSelector(JuvantiaTradeHub.initialize.selector, address(eurc), admin);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        tradeHub = JuvantiaTradeHub(address(proxy));

        // Fund seller and buyer
        assetToken.transfer(seller, 100000 * 10**18);
        eurc.transfer(buyer, 100000 * 10**6);

        vm.stopPrank();
    }

    function testCreateOrder() public {
        vm.startPrank(seller);
        assetToken.approve(address(tradeHub), 100 * 10**18);
        uint256 orderId = tradeHub.createOrder(address(assetToken), 100 * 10**18, 5 * 10**6);
        vm.stopPrank();

        (address oSeller, address oAssetToken, uint256 amt, uint256 price, bool active) = tradeHub.orders(orderId);
        assertEq(oSeller, seller);
        assertEq(oAssetToken, address(assetToken));
        assertEq(amt, 100 * 10**18);
        assertEq(price, 5 * 10**6);
        assertTrue(active);
    }

    function testFillOrder() public {
        // Seller creates order for 100 units at 5 EURC each
        vm.startPrank(seller);
        assetToken.approve(address(tradeHub), 100 * 10**18);
        uint256 orderId = tradeHub.createOrder(address(assetToken), 100 * 10**18, 5 * 10**6);
        vm.stopPrank();

        // Buyer fills 40 units
        vm.startPrank(buyer);
        uint256 amountToBuy = 40 * 10**18;
        uint256 totalCost = (amountToBuy * 5 * 10**6) / 10**18; // 200 * 10**6 EURC
        eurc.approve(address(tradeHub), totalCost);
        tradeHub.fillOrder(orderId, amountToBuy);
        vm.stopPrank();

        // Assertions
        (,, uint256 remaining,, bool active) = tradeHub.orders(orderId);
        assertEq(remaining, 60 * 10**18);
        assertTrue(active);
        assertEq(assetToken.balanceOf(buyer), amountToBuy);
        assertEq(tradeHub.pendingWithdrawals(seller), totalCost);
    }

    function testWithdraw() public {
        // Setup order and fill
        testFillOrder();

        uint256 sellerBalanceBefore = eurc.balanceOf(seller);
        uint256 pending = tradeHub.pendingWithdrawals(seller);

        vm.startPrank(seller);
        tradeHub.withdraw();
        vm.stopPrank();

        assertEq(eurc.balanceOf(seller), sellerBalanceBefore + pending);
        assertEq(tradeHub.pendingWithdrawals(seller), 0);
    }

    function testCancelOrder() public {
        vm.startPrank(seller);
        assetToken.approve(address(tradeHub), 100 * 10**18);
        uint256 orderId = tradeHub.createOrder(address(assetToken), 100 * 10**18, 5 * 10**6);
        
        uint256 balanceBeforeCancel = assetToken.balanceOf(seller);
        tradeHub.cancelOrder(orderId);
        uint256 balanceAfterCancel = assetToken.balanceOf(seller);
        vm.stopPrank();

        assertEq(balanceAfterCancel - balanceBeforeCancel, 100 * 10**18);
        (,, uint256 remaining,, bool active) = tradeHub.orders(orderId);
        assertEq(remaining, 0);
        assertFalse(active);
    }
}
