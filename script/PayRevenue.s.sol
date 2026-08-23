// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RevenueRegistry } from "../src/source/RevenueRegistry.sol";

contract PayRevenue is Script {
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    address internal constant CIRCLE_SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function run() external {
        require(block.chainid == SEPOLIA_CHAIN_ID, "PayRevenue: not Sepolia");

        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address payer = vm.addr(privateKey);

        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        address business = vm.envAddress("BUSINESS_ADDRESS");

        // Raw USDC units. USDC has 6 decimals:
        // 1 USDC = 1_000_000
        // 10 USDC = 10_000_000
        uint256 amount = vm.envUint("PAYMENT_AMOUNT");
        require(amount > 0, "PayRevenue: zero amount");

        string memory paymentRef = vm.envString("PAYMENT_REF");
        bytes32 paymentId = keccak256(bytes(paymentRef));

        IERC20 usdc = IERC20(CIRCLE_SEPOLIA_USDC);
        RevenueRegistry registry = RevenueRegistry(registryAddress);

        uint256 balance = usdc.balanceOf(payer);
        require(balance >= amount, "PayRevenue: insufficient Sepolia USDC");

        console2.log("Payer:", payer);
        console2.log("Business:", business);
        console2.log("Registry:", registryAddress);
        console2.log("Amount (raw USDC units):", amount);
        console2.logBytes32(paymentId);

        vm.startBroadcast(privateKey);

        // Tx 1: authorize FlowCred to transfer exactly this payment.
        require(usdc.approve(registryAddress, amount), "PayRevenue: approve failed");

        // Tx 2: this is the transaction Attestcoin will later prove.
        registry.payBusiness(business, amount, paymentId);

        vm.stopBroadcast();

        console2.log("Revenue payment broadcast successfully.");
    }
}
