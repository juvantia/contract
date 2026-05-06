// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/JuvantiaAsset.sol";
import "../src/JuvantiaAssetFabrica.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployJuvantia is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Deploy implementation logic for the asset
        JuvantiaAsset assetImpl = new JuvantiaAsset();
        
        // 2. Deploy implementation logic for the factory
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(assetImpl));

        // 3. Deploy ERC1967 Proxy for the fabrica (makes factory upgradeable)
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeWithSelector(JuvantiaAssetFabrica.initialize.selector)
        );

        console.log("JuvantiaAsset Logic Address:", address(assetImpl));
        console.log("Factory Proxy Address (USE THIS IN BACKEND):", address(proxy));

        vm.stopBroadcast();
    }
}