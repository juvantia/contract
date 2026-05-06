// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/JuvantiaAsset.sol";
import "../src/JuvantiaAssetFabrica.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract JuvantiaTest is Test {
    JuvantiaAsset assetImpl;
    JuvantiaAssetFabrica fabrica;
    address owner = address(0x123);
    address user = address(0x456);

    // setUp is executed before EACH test
    function setUp() public {
        // 1. Deploy the asset implementation
        assetImpl = new JuvantiaAsset();
        
        // 2. Deploy the factory logic
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(assetImpl));

        // 3. Deploy the proxy for the factory
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeWithSelector(JuvantiaAssetFabrica.initialize.selector)
        );

        // Bind the factory interface to the proxy address
        fabrica = JuvantiaAssetFabrica(address(proxy));
    }

    // Example of a successful test
    function testCreateAsset() public {
        // The factory is currently owned by the JuvantiaTest contract
        
        string memory name = "Test Token";
        string memory symbol = "TTK";
        
        // Expect the factory to emit the AssetCreated event (if testing events is needed)
        // vm.expectEmit(true, true, false, true);
        // emit JuvantiaAssetFabrica.AssetCreated(..., user, name, symbol);

        // Call the factory function
        address newAsset = fabrica.createAsset(name, symbol, user);

        // Check that the address is not zero
        assertTrue(newAsset != address(0));

        // Check the parameters of the created token
        JuvantiaAsset token = JuvantiaAsset(newAsset);
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        
        // The owner of the token contract (admin) becomes the owner of the factory (i.e. this test contract)
        assertEq(token.owner(), address(this));

        // Check that 100,000 tokens were minted to the user (initialOwner)
        uint256 expectedBalance = 100_000 * 10 ** token.decimals();
        assertEq(token.balanceOf(user), expectedBalance);
    }

    // Example of a test that checks for an expected revert
    function test_RevertWhen_NotOwnerCreateAsset() public {
        // Change the transaction sender to a regular user (not the factory owner)
        vm.prank(user);
        
        // Specify that the next transaction should fail with OwnableUnauthorizedAccount(user)
        // OpenZeppelin v5 uses the custom error OwnableUnauthorizedAccount(address account)
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        
        fabrica.createAsset("Fail Token", "FAIL", user);
    }

    function test_AdminBurn() public {
        address newAsset = fabrica.createAsset("Burn Token", "BRN", user);
        JuvantiaAsset token = JuvantiaAsset(newAsset);

        uint256 decimals = token.decimals();
        uint256 initialBalance = 100_000 * 10 ** decimals;
        uint256 burnAmount = 10_000 * 10 ** decimals;

        // Admin (the current contract) calls the burn function
        token.burn(user, burnAmount);

        // Check that the user's balance decreased
        assertEq(token.balanceOf(user), initialBalance - burnAmount);
        
        // Check that the total supply also decreased
        assertEq(token.totalSupply(), initialBalance - burnAmount);
    }

    function test_RevertWhen_UserTriesToBurn() public {
        address newAsset = fabrica.createAsset("Burn Token", "BRN", user);
        JuvantiaAsset token = JuvantiaAsset(newAsset);

        uint256 burnAmount = 10_000 * 10 ** token.decimals();

        // The user tries to burn their own tokens
        vm.prank(user);
        
        // Expect OwnableUnauthorizedAccount error since burn has the onlyOwner modifier
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        
        token.burn(user, burnAmount);
    }
}