// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployJuvantiaTradeHub is Script {
    function run() external {
        require(block.chainid == vm.envUint("BLOCKCHAIN_CHAIN_ID"), "Unexpected blockchain");
        address euroToken = vm.envAddress("EURO_TOKEN_ADDRESS");
        address distributor = vm.envAddress("REVENUE_DISTRIBUTOR_ADDRESS");
        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();
        JuvantiaTradeHub implementation = new JuvantiaTradeHub();
        address proxy = address(new ERC1967Proxy(address(implementation),
            abi.encodeCall(JuvantiaTradeHub.initialize, (euroToken, deployer, distributor))));
        vm.stopBroadcast();
        console.log("JuvantiaTradeHub implementation", address(implementation));
        console.log("JuvantiaTradeHub", proxy);
    }
}
