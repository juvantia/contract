// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployJuvantiaTradeHub is Script {
    function run() external {
        require(block.chainid == 10200, "Chiado only");
        address distributor = vm.envAddress("REVENUE_DISTRIBUTOR_ADDRESS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        JuvantiaTradeHub implementation = new JuvantiaTradeHub();
        address proxy = address(new ERC1967Proxy(address(implementation),
            abi.encodeCall(JuvantiaTradeHub.initialize, (0x8106F0830f18d2CDa1c0AD7d929a2941F849DF54, deployer, distributor))));
        vm.stopBroadcast();
        console.log("JuvantiaTradeHub implementation", address(implementation));
        console.log("JuvantiaTradeHub", proxy);
    }
}
