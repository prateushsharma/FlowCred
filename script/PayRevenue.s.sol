// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RevenueRegistry } from "../src/source/RevenueRegistry.sol";

contract PayRevenue is Script {
    function run() external {
        require(block.chainid == 11155111, "PayRevenue: Ethereum Sepolia only");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address customer = vm.addr(privateKey);
        address registryAddress = vm.envAddress("REVENUE_REGISTRY");
        address business = vm.envAddress("BUSINESS_ADDRESS");
        uint256 amount = vm.envUint("AMOUNT_USDC") * 1e6;
        string memory paymentRef = vm.envString("PAYMENT_REF");
        bytes32 paymentId = keccak256(bytes(paymentRef));

        RevenueRegistry registry = RevenueRegistry(registryAddress);
        IERC20 token = registry.paymentToken();

        vm.startBroadcast(privateKey);
        token.approve(registryAddress, amount);
        registry.payBusiness(business, amount, paymentId);
        vm.stopBroadcast();

        console2.log("FlowCred revenue payment emitted");
        console2.log("Customer:   ", customer);
        console2.log("Business:   ", business);
        console2.log("Token:      ", address(token));
        console2.log("Amount raw: ", amount);
        console2.log("Payment ID:");
        console2.logBytes32(paymentId);
    }
}
