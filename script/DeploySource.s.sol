// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";
import { RevenueRegistry } from "../src/source/RevenueRegistry.sol";

contract DeploySource is Script {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    // Circle official USDC on Ethereum Sepolia.
    address internal constant CIRCLE_SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external returns (RevenueRegistry registry) {
        require(block.chainid == SEPOLIA_CHAIN_ID, "DeploySource: not Sepolia");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        registry = new RevenueRegistry(CIRCLE_SEPOLIA_USDC);
        vm.stopBroadcast();

        console2.log("RevenueRegistry:", address(registry));
        console2.log("USDC:", CIRCLE_SEPOLIA_USDC);
    }
}
