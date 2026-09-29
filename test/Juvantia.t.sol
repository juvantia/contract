// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProtocolFixture} from "./ProtocolFixture.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";

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

    function testCreateSubAssetCellaLinkedToParentDomus() public {
        bytes32 domusId = keccak256("domus-DM-3553");
        address domus = fabrica.createAsset(domusId, "ROBOHOUSE DM-3553", "DM-3553", alice);

        bytes32 cella1Id = keccak256("cella-DM-3553-C1");
        address cella1 = fabrica.createSubAsset(domusId, cella1Id, "ROBOHOUSE Cella 1", "DM-3553-C1", bob);

        bytes32 cella2Id = keccak256("cella-DM-3553-C2");
        address cella2 = fabrica.createSubAsset(domusId, cella2Id, "ROBOHOUSE Cella 2", "DM-3553-C2", carol);

        assertEq(fabrica.parentAsset(cella1), domus);
        assertEq(fabrica.parentAsset(cella2), domus);
        assertEq(fabrica.parentAsset(domus), address(0));

        assertEq(fabrica.subAssetCount(domus), 2);
        address[] memory subs = fabrica.getSubAssets(domus);
        assertEq(subs.length, 2);
        assertEq(subs[0], cella1);
        assertEq(subs[1], cella2);

        // Check Cella properties
        assertEq(JuvantiaAsset(cella1).symbol(), "DM-3553-C1");
        assertEq(JuvantiaAsset(cella1).name(), "ROBOHOUSE Cella 1");
        assertEq(JuvantiaAsset(cella1).balanceOf(bob), 100_000 ether);
        assertEq(JuvantiaAsset(cella2).balanceOf(carol), 100_000 ether);
    }

    function testCreateSubAssetFailsIfParentDoesNotExist() public {
        bytes32 nonExistentParent = keccak256("non-existent");
        bytes32 cellaId = keccak256("cella-orphan");
        vm.expectRevert("Parent asset does not exist");
        fabrica.createSubAsset(nonExistentParent, cellaId, "Orphan Cella", "DM-9999-C1", bob);
    }
}
