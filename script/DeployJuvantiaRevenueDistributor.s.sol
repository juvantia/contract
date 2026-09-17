// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";

contract DeployJuvantiaRevenueDistributor is Script {
    function run() external {
        require(block.chainid == vm.envUint("BLOCKCHAIN_CHAIN_ID"), "Unexpected blockchain");
        address euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        address aerarium = vm.envOr("AERARIUM_ADDRESS", address(0));
        JuvantiaRevenueDistributor distributor = new JuvantiaRevenueDistributor(
            euroToken, deployer, aerarium);
        vm.stopBroadcast();
        console.log("JuvantiaRevenueDistributor", address(distributor));
    }
}
