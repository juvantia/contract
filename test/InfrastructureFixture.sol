// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {JuvantiaAerarium} from "../src/JuvantiaAerarium.sol";
import {JuvantiaRevenueDistributor} from "../src/JuvantiaRevenueDistributor.sol";
import {JuvantiaPaymentRegistry} from "../src/JuvantiaPaymentRegistry.sol";

/// @dev Economic regressions exercise the same atomic proxy initialization as the release script.
library InfrastructureFixture {
    function budget(address token, address owner) internal returns (JuvantiaAerarium) {
        return JuvantiaAerarium(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaAerarium()), abi.encodeCall(JuvantiaAerarium.initialize, (token, owner))
                )
            )
        );
    }

    function distributor(address token, address owner, address treasury) internal returns (JuvantiaRevenueDistributor) {
        return JuvantiaRevenueDistributor(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaRevenueDistributor()),
                    abi.encodeCall(JuvantiaRevenueDistributor.initialize, (token, owner, treasury))
                )
            )
        );
    }

    function registry(address owner) internal returns (JuvantiaPaymentRegistry) {
        return JuvantiaPaymentRegistry(
            address(
                new ERC1967Proxy(
                    address(new JuvantiaPaymentRegistry()), abi.encodeCall(JuvantiaPaymentRegistry.initialize, (owner))
                )
            )
        );
    }
}
