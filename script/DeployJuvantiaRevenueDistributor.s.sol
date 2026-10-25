// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";

contract DeployJuvantiaRevenueDistributor is Script {
    function run() external {
        require(block.chainid == vm.envUint("BLOCKCHAIN_CHAIN_ID"), "Unexpected blockchain");
        address euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        address aerarium = vm.envAddress("AERARIUM_ADDRESS");
        address registry = vm.envAddress("PAYMENT_REGISTRY_ADDRESS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        JuvantiaRevenueDistributor implementation = new JuvantiaRevenueDistributor();
        JuvantiaRevenueDistributor distributor = JuvantiaRevenueDistributor(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(JuvantiaRevenueDistributor.initialize, (euroToken, deployer, aerarium))
                )
            )
        );
        distributor.setPaymentRegistry(registry);
        vm.stopBroadcast();
        console.log("JuvantiaRevenueDistributor implementation", address(implementation));
        console.log("JuvantiaRevenueDistributor", address(distributor));
    }
}
