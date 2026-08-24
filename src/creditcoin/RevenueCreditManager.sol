// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title RevenueCreditManager
/// @notice Stores revenue that has already been authenticated by FlowCred's ASC.
/// @dev Credit scoring/lending will be layered on top in later milestones.
contract RevenueCreditManager {
    error NotAdmin();
    error NotASC();
    error ZeroAddress();
    error ZeroAmount();
    error ASCLocked();
    error DuplicatePaymentId();

    address public immutable ADMIN;

    address public asc;
    bool public ascLocked;

    mapping(address business => uint256 amount) public verifiedRevenue;
    mapping(bytes32 paymentId => bool processed) public processedPaymentIds;

    event ASCConfigured(address indexed asc);
    event ASCLockEnabled(address indexed asc);

    event VerifiedRevenueRecorded(
        address indexed business,
        address indexed payer,
        uint256 amount,
        bytes32 indexed paymentId,
        bytes32 queryId
    );

    constructor(address admin_) {
        if (admin_ == address(0)) revert ZeroAddress();
        ADMIN = admin_;
    }

    modifier onlyAdmin() {
        if (msg.sender != ADMIN) revert NotAdmin();
        _;
    }

    modifier onlyASC() {
        if (msg.sender != asc) revert NotASC();
        _;
    }

    /// @notice Set the ASC allowed to write verified revenue.
    /// @dev Can be updated during deployment, then permanently locked.
    function setASC(address asc_) external onlyAdmin {
        if (ascLocked) revert ASCLocked();
        if (asc_ == address(0)) revert ZeroAddress();

        asc = asc_;
        emit ASCConfigured(asc_);
    }

    /// @notice Permanently freezes the authorized ASC address.
    function lockASC() external onlyAdmin {
        if (asc == address(0)) revert ZeroAddress();
        ascLocked = true;
        emit ASCLockEnabled(asc);
    }

    /// @notice Called only by RevenueASC after a cross-chain proof has passed.
    function recordVerifiedRevenue(
        address business,
        address payer,
        uint256 amount,
        bytes32 paymentId,
        bytes32 queryId
    ) external onlyASC {
        if (business == address(0) || payer == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (processedPaymentIds[paymentId]) revert DuplicatePaymentId();

        processedPaymentIds[paymentId] = true;
        verifiedRevenue[business] += amount;

        emit VerifiedRevenueRecorded(business, payer, amount, paymentId, queryId);
    }
}
