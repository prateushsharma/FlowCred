// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { MockUSDC } from "../../src/source/MockUSDC.sol";
import { RevenueRegistry } from "../../src/source/RevenueRegistry.sol";

contract RevenueRegistryTest is Test {
    uint256 internal constant USDC = 1e6;

    address internal owner = makeAddr("owner");
    address internal customer = makeAddr("customer");
    address internal business = makeAddr("business");

    MockUSDC internal token;
    RevenueRegistry internal registry;

    event RevenuePaymentForCredit(
        address indexed business,
        address indexed payer,
        bytes32 indexed paymentId,
        address token,
        uint256 amount
    );

    function setUp() public {
        token = new MockUSDC(owner);
        registry = new RevenueRegistry(address(token));

        vm.prank(owner);
        token.mint(customer, 10_000 * USDC);

        vm.prank(customer);
        token.approve(address(registry), type(uint256).max);
    }

    function testPayBusinessTransfersFundsAndEmitsCanonicalEvent() public {
        uint256 amount = 100 * USDC;
        bytes32 paymentId = keccak256("invoice-001");

        vm.expectEmit(true, true, true, true, address(registry));
        emit RevenuePaymentForCredit(business, customer, paymentId, address(token), amount);

        vm.prank(customer);
        registry.payBusiness(business, amount, paymentId);

        assertEq(token.balanceOf(business), amount);
        assertEq(token.balanceOf(customer), 10_000 * USDC - amount);
    }

    function testRevertsForZeroBusiness() public {
        vm.expectRevert(RevenueRegistry.ZeroAddress.selector);
        vm.prank(customer);
        registry.payBusiness(address(0), 100 * USDC, keccak256("invoice-001"));
    }

    function testRevertsForZeroAmount() public {
        vm.expectRevert(RevenueRegistry.ZeroAmount.selector);
        vm.prank(customer);
        registry.payBusiness(business, 0, keccak256("invoice-001"));
    }

    function testRevertsForZeroPaymentId() public {
        vm.expectRevert(RevenueRegistry.ZeroPaymentId.selector);
        vm.prank(customer);
        registry.payBusiness(business, 100 * USDC, bytes32(0));
    }

    function testRevertsForTrivialSelfPayment() public {
        vm.expectRevert(RevenueRegistry.SelfPaymentNotAllowed.selector);
        vm.prank(customer);
        registry.payBusiness(customer, 100 * USDC, keccak256("invoice-001"));
    }

    function testRevertsWithoutAllowance() public {
        address unapprovedCustomer = makeAddr("unapproved-customer");

        vm.prank(owner);
        token.mint(unapprovedCustomer, 100 * USDC);

        vm.expectRevert();
        vm.prank(unapprovedCustomer);
        registry.payBusiness(business, 100 * USDC, keccak256("invoice-002"));
    }

    function testFuzzPayBusiness(uint96 rawAmount, bytes32 paymentId) public {
        vm.assume(paymentId != bytes32(0));
        uint256 amount = bound(uint256(rawAmount), 1, 1_000_000 * USDC);

        vm.prank(owner);
        token.mint(customer, amount);

        uint256 businessBefore = token.balanceOf(business);

        vm.prank(customer);
        registry.payBusiness(business, amount, paymentId);

        assertEq(token.balanceOf(business), businessBefore + amount);
    }
}
