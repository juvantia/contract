// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";

contract JuvantiaTest is ProtocolFixture {
    function testCreateAsset() public view {
        assertEq(asset.balanceOf(alice), 100_000 ether);
        assertEq(asset.totalSupply(), 100_000 ether);
        assertEq(asset.revenueDistributor(), address(revenue));
        assertEq(asset.owner(), address(this));
        assertEq(fabrica.assetById(keccak256("asset-1")), address(asset));
        assertEq(fabrica.assetCount(), 1);
        assertTrue(revenue.registeredAssets(address(asset)));
    }

    function testDuplicatePhysicalAssetCannotBeMinted() public {
        vm.expectRevert("Invalid or duplicate asset ID");
        fabrica.createAsset(keccak256("asset-1"), "Duplicate", alice);
    }

    function testNonOwnerCannotRegisterAsset() public {
        vm.prank(bob);
        vm.expectRevert();
        fabrica.createAsset(keccak256("asset-2"), "Unauthorized", bob);
    }

    function testFixedSupplyHasNoAdminMintOrBurn() public {
        (bool minted,) = address(asset).call(abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether));
        (bool burned,) = address(asset).call(abi.encodeWithSignature("burn(address,uint256)", alice, 1 ether));
        assertFalse(minted);
        assertFalse(burned);
        assertEq(asset.totalSupply(), 100_000 ether);
    }

    function testCannotReinitializeAssetOrFactory() public {
        vm.expectRevert();
        asset.initialize("Override", "APU", bob, bob, address(revenue));
        vm.expectRevert();
        fabrica.initialize(bob, address(revenue));
    }
}
