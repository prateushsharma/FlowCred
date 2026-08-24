// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { RevenueCreditManager } from "../../src/creditcoin/RevenueCreditManager.sol";

contract RevenueCreditManagerTest is Test {
    RevenueCreditManager internal manager;

    address internal admin = makeAddr("admin");
    address internal asc = makeAddr("asc");
    address internal attacker = makeAddr("attacker");
    address internal business = makeAddr("business");
    address internal payer = makeAddr("payer");

    function setUp() public {
        manager = new RevenueCreditManager(admin);

        vm.prank(admin);
        manager.setASC(asc);
    }

    function testASCRecordsVerifiedRevenue() public {
        bytes32 paymentId = keccak256("payment-1");
        bytes32 queryId = keccak256("query-1");

        vm.prank(asc);
        manager.recordVerifiedRevenue(business, payer, 1_000_000, paymentId, queryId);

        assertEq(manager.verifiedRevenue(business), 1_000_000);
        assertTrue(manager.processedPaymentIds(paymentId));
    }

    function testOnlyASCCanRecordRevenue() public {
        vm.expectRevert(RevenueCreditManager.NotASC.selector);

        vm.prank(attacker);
        manager.recordVerifiedRevenue(
            business, payer, 1_000_000, keccak256("payment"), keccak256("query")
        );
    }

    function testDuplicatePaymentIdIsRejected() public {
        bytes32 paymentId = keccak256("same-payment");

        vm.startPrank(asc);

        manager.recordVerifiedRevenue(business, payer, 1_000_000, paymentId, keccak256("query-1"));

        vm.expectRevert(RevenueCreditManager.DuplicatePaymentId.selector);

        manager.recordVerifiedRevenue(business, payer, 1_000_000, paymentId, keccak256("query-2"));

        vm.stopPrank();
    }

    function testAdminCanLockASCConfiguration() public {
        vm.startPrank(admin);
        manager.lockASC();

        vm.expectRevert(RevenueCreditManager.ASCLocked.selector);
        manager.setASC(makeAddr("replacement"));

        vm.stopPrank();
    }

    function testNonAdminCannotSetASC() public {
        vm.expectRevert(RevenueCreditManager.NotAdmin.selector);

        vm.prank(attacker);
        manager.setASC(attacker);
    }
}
