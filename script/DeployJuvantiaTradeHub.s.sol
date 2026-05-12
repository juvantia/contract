// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {JuvantiaTradeHub} from "../src/JuvantiaTradeHub.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployJuvantiaTradeHub is Script {
    function run() public {
        address eurcAddress = vm.envAddress("EURC_ADDRESS");

        vm.startBroadcast();
        address deployer = msg.sender;

        // 1. Deploy Implementation
        JuvantiaTradeHub implementation = new JuvantiaTradeHub();
        console.log("JuvantiaTradeHub Implementation deployed at:", address(implementation));

        // 2. Prepare Initialization Data
        bytes memory data = abi.encodeWithSelector(
            JuvantiaTradeHub.initialize.selector,
            eurcAddress,
            deployer
        );

        // 3. Deploy Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        console.log("JuvantiaTradeHub Proxy (Active Contract) deployed at:", address(proxy));

        vm.stopBroadcast();
    }
}
