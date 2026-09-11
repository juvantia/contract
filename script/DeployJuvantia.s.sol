// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAsset} from "../src/JuvantiaAsset.sol";
import {JuvantiaAssetFabrica} from "../src/JuvantiaAssetFabrica.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaLeasingHub} from "../src/JuvantiaLeasingHub.sol";
import {JuvantiaServicePayments} from "../src/JuvantiaServicePayments.sol";

contract DeployJuvantia is Script {
    address constant EURE = 0x8106F0830f18d2CDa1c0AD7d929a2941F849DF54;

    function run() external {
        require(block.chainid == 10200, "Chiado only");
        uint256 taxBps = vm.envUint("LEASE_TAX_BPS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        JuvantiaRevenueDistributor revenue = new JuvantiaRevenueDistributor(EURE, deployer);
        JuvantiaAsset assetImpl = new JuvantiaAsset();
        JuvantiaAssetFabrica factoryImpl = new JuvantiaAssetFabrica(address(assetImpl));
        JuvantiaAssetFabrica fabrica = JuvantiaAssetFabrica(address(new ERC1967Proxy(
            address(factoryImpl), abi.encodeCall(JuvantiaAssetFabrica.initialize, (deployer, address(revenue)))
        )));
        revenue.setRegistrar(address(fabrica), true);
        JuvantiaTradeHub tradeImpl = new JuvantiaTradeHub();
        address trade = address(new ERC1967Proxy(address(tradeImpl),
            abi.encodeCall(JuvantiaTradeHub.initialize, (EURE, deployer, address(revenue)))));
        revenue.setEscrow(trade, true);
        JuvantiaAerarium aerarium = new JuvantiaAerarium(EURE, deployer);
        JuvantiaLeasingHub leasing = new JuvantiaLeasingHub(EURE, address(aerarium), address(revenue), deployer, taxBps);
        JuvantiaServicePayments services = new JuvantiaServicePayments(EURE);
        vm.stopBroadcast();

        console.log("Deployer", deployer);
        console.log("JuvantiaAsset", address(assetImpl));
        console.log("JuvantiaAssetFabrica implementation", address(factoryImpl));
        console.log("JuvantiaAssetFabrica", address(fabrica));
        console.log("JuvantiaTradeHub implementation", address(tradeImpl));
        console.log("JuvantiaTradeHub", trade);
        console.log("JuvantiaRevenueDistributor", address(revenue));
        console.log("JuvantiaAerarium", address(aerarium));
        console.log("JuvantiaLeasingHub", address(leasing));
        console.log("JuvantiaServicePayments", address(services));
    }
}
