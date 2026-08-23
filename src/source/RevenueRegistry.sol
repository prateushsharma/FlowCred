// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RevenueRegistry
/// @notice Minimal source-chain contract for FlowCred.
/// @dev Users pay a business using one approved ERC20. A dedicated event is emitted so an
///      Attestcoin readability worker can prove the transaction to FlowCred's ASC on Creditcoin.
contract RevenueRegistry {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error ZeroAmount();
    error ZeroPaymentId();
    error SelfPaymentNotAllowed();
    error UnexpectedReceivedAmount(uint256 expected, uint256 actual);

    IERC20 public immutable paymentToken;

    /// @notice Canonical source-chain event consumed by FlowCred's future Attestcoin worker/ASC.
    /// @dev Three indexed fields make worker filtering straightforward while amount/token remain
    ///      directly available in the receipt log data for ASC decoding.
    event RevenuePaymentForCredit(
        address indexed business,
        address indexed payer,
        bytes32 indexed paymentId,
        address token,
        uint256 amount
    );

    constructor(address paymentToken_) {
        if (paymentToken_ == address(0)) revert ZeroAddress();
        paymentToken = IERC20(paymentToken_);
    }

    /// @notice Pay a business and emit an Attestcoin-specific revenue event.
    /// @param business The business receiving the revenue.
    /// @param amount Token amount in the token's smallest unit (6 decimals for USDC).
    /// @param paymentId Application-level payment/invoice identifier.
    function payBusiness(address business, uint256 amount, bytes32 paymentId) external {
        if (business == address(0)) revert ZeroAddress();
        if (business == msg.sender) revert SelfPaymentNotAllowed();
        if (amount == 0) revert ZeroAmount();
        if (paymentId == bytes32(0)) revert ZeroPaymentId();

        uint256 balanceBefore = paymentToken.balanceOf(business);
        paymentToken.safeTransferFrom(msg.sender, business, amount);
        uint256 received = paymentToken.balanceOf(business) - balanceBefore;

        // FlowCred's credit calculation must not overstate revenue for fee-on-transfer tokens.
        if (received != amount) revert UnexpectedReceivedAmount(amount, received);

        emit RevenuePaymentForCredit(business, msg.sender, paymentId, address(paymentToken), amount);
    }
}
