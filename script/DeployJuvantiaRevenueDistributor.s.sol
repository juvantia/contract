// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";

contract DeployJuvantiaRevenueDistributor is Script {
    function run() external {
        require(block.chainid == 10200, "Chiado only");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        JuvantiaRevenueDistributor distributor = new JuvantiaRevenueDistributor(
            0x8106F0830f18d2CDa1c0AD7d929a2941F849DF54, deployer);
        vm.stopBroadcast();
        console.log("JuvantiaRevenueDistributor", address(distributor));
    }
}
