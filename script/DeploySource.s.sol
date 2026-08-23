// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { RevenueRegistry } from "../src/source/RevenueRegistry.sol";

contract DeploySource is Script {
    // Official Circle USDC deployment on Ethereum Sepolia.
    address internal constant CIRCLE_SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external returns (RevenueRegistry registry) {
        require(block.chainid == 11155111, "DeploySource: Ethereum Sepolia only");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);
        registry = new RevenueRegistry(CIRCLE_SEPOLIA_USDC);
        vm.stopBroadcast();

        console2.log("FlowCred source contract deployed");
        console2.log("Deployer:        ", deployer);
        console2.log("Circle Sepolia USDC:", CIRCLE_SEPOLIA_USDC);
        console2.log("RevenueRegistry: ", address(registry));
    }
}
