// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAssetFabrica} from "../src/JuvantiaAssetFabrica.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";

contract DeployJuvantia is Script {
    function run() external {
        require(block.chainid == vm.envUint("BLOCKCHAIN_CHAIN_ID"), "Unexpected blockchain");
        address euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        JuvantiaAerarium aerarium = new JuvantiaAerarium(euroToken, deployer);
        JuvantiaRevenueDistributor revenue = new JuvantiaRevenueDistributor(euroToken, deployer, address(aerarium));
        JuvantiaAsset assetImpl = new JuvantiaAsset();
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(assetImpl));
        JuvantiaAssetFabrica fabrica = JuvantiaAssetFabrica(address(new ERC1967Proxy(
            address(factoryImpl), abi.encodeCall(JuvantiaAssetFabrica.initialize, (deployer, address(revenue)))
        )));
        revenue.setRegistrar(address(fabrica), true);
        JuvantiaTradeHub tradeImpl = new JuvantiaTradeHub();
        address trade = address(new ERC1967Proxy(address(tradeImpl),
            abi.encodeCall(JuvantiaTradeHub.initialize, (euroToken, deployer, address(revenue)))));
        revenue.setEscrow(trade, true);
        JuvantiaServicePayments services = new JuvantiaServicePayments(euroToken);
        vm.stopBroadcast();

        console.log("Deployer", deployer);
        console.log("JuvantiaAerarium", address(aerarium));
        console.log("JuvantiaRevenueDistributor", address(revenue));
        console.log("JuvantiaAsset", address(assetImpl));
        console.log("JuvantiaAssetFabrica implementation", address(factoryImpl));
        console.log("JuvantiaAssetFabrica", address(fabrica));
        console.log("JuvantiaTradeHub implementation", address(tradeImpl));
        console.log("JuvantiaTradeHub", trade);
        console.log("JuvantiaServicePayments", address(services));
    }
}
