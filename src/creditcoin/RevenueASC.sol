// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { EvmV1Decoder } from "@gluwa/usc-contracts/contracts/decoding/EvmV1Decoder.sol";

import { INativeQueryVerifier, NativeQueryVerifierLib } from "./VerifierInterface.sol";

import { RevenueCreditManager } from "./RevenueCreditManager.sol";

/// @title FlowCred RevenueASC
/// @notice Verifies Sepolia revenue transactions through Attestcoin and forwards
///         authenticated revenue into RevenueCreditManager.
contract RevenueASC {
    error InvalidSourceChain(uint64 chainKey);
    error QueryAlreadyProcessed();
    error VerificationFailed();
    error UnsupportedTransactionType();
    error SourceTransactionFailed();
    error RevenueEventNotFound();
    error InvalidRevenueEvent();
    error InvalidRevenueSource();
    error InvalidRevenueToken();
    error InvalidRevenueAmount();
    error InvalidBusiness();
    error InvalidPayer();

    uint64 public constant SEPOLIA_CHAIN_KEY = 1;

    // keccak256(
    //   "RevenuePaymentForCredit(address,address,bytes32,address,uint256)"
    // )
    bytes32 public constant REVENUE_EVENT_SIGNATURE =
        keccak256("RevenuePaymentForCredit(address,address,bytes32,address,uint256)");

    INativeQueryVerifier public immutable VERIFIER;
    RevenueCreditManager public immutable CREDIT_MANAGER;

    address public immutable SOURCE_REGISTRY;
    address public immutable SOURCE_USDC;

    mapping(bytes32 queryId => bool processed) public processedQueries;

    event RevenueProofConsumed(
        bytes32 indexed queryId,
        address indexed business,
        address indexed payer,
        uint256 amount,
        bytes32 paymentId
    );

    constructor(address sourceRegistry_, address sourceUsdc_, address creditManager_) {
        if (
            sourceRegistry_ == address(0) || sourceUsdc_ == address(0)
                || creditManager_ == address(0)
        ) {
            revert InvalidRevenueSource();
        }

        SOURCE_REGISTRY = sourceRegistry_;
        SOURCE_USDC = sourceUsdc_;
        CREDIT_MANAGER = RevenueCreditManager(creditManager_);
        VERIFIER = NativeQueryVerifierLib.getVerifier();
    }

    /// @notice Verify one source-chain transaction and ingest its revenue event.
    /// @dev The worker is permissionless/untrusted. Security comes from:
    ///      - chainKey authentication
    ///      - native proof verification
    ///      - successful receipt check
    ///      - source contract address check
    ///      - exact event signature/schema
    ///      - approved token check
    ///      - replay protection
    function execute(
        uint64 chainKey,
        uint64 blockHeight,
        bytes calldata encodedTransaction,
        bytes32 merkleRoot,
        INativeQueryVerifier.MerkleProofEntry[] calldata siblings,
        bytes32 lowerEndpointDigest,
        bytes32[] calldata continuityRoots
    ) external returns (bool success) {
        if (chainKey != SEPOLIA_CHAIN_KEY) {
            revert InvalidSourceChain(chainKey);
        }

        INativeQueryVerifier.MerkleProof memory merkleProof =
            INativeQueryVerifier.MerkleProof({ root: merkleRoot, siblings: siblings });

        uint64 txIndex = VERIFIER.calculateTxIndex(merkleProof);
        bytes32 queryId = keccak256(abi.encodePacked(chainKey, blockHeight, txIndex));

        if (processedQueries[queryId]) revert QueryAlreadyProcessed();

        INativeQueryVerifier.ContinuityProof memory continuityProof =
            INativeQueryVerifier.ContinuityProof({
                lowerEndpointDigest: lowerEndpointDigest, roots: continuityRoots
            });

        bool verified = VERIFIER.verifyAndEmit(
            chainKey, blockHeight, encodedTransaction, merkleProof, continuityProof
        );

        if (!verified) revert VerificationFailed();

        // The Block Prover proves inclusion, not successful execution.
        uint8 txType = EvmV1Decoder.getTransactionType(encodedTransaction);
        if (!EvmV1Decoder.isValidTransactionType(txType)) {
            revert UnsupportedTransactionType();
        }

        EvmV1Decoder.ReceiptFields memory receipt =
            EvmV1Decoder.decodeReceiptFields(encodedTransaction);

        if (receipt.receiptStatus != 1) revert SourceTransactionFailed();

        EvmV1Decoder.LogEntry[] memory revenueLogs =
            EvmV1Decoder.getLogsByEventSignature(receipt, REVENUE_EVENT_SIGNATURE);

        (
            bool found,
            address business,
            address payer,
            address token,
            uint256 amount,
            bytes32 paymentId
        ) = _findValidRevenueLog(revenueLogs);

        if (!found) revert RevenueEventNotFound();
        if (token != SOURCE_USDC) revert InvalidRevenueToken();
        if (amount == 0) revert InvalidRevenueAmount();
        if (business == address(0)) revert InvalidBusiness();
        if (payer == address(0) || payer == business) revert InvalidPayer();

        // Mark before external business-logic call. A revert below unwinds this,
        // so a failed business update cannot consume the proof permanently.
        processedQueries[queryId] = true;

        CREDIT_MANAGER.recordVerifiedRevenue(business, payer, amount, paymentId, queryId);

        emit RevenueProofConsumed(queryId, business, payer, amount, paymentId);

        return true;
    }

    function _findValidRevenueLog(EvmV1Decoder.LogEntry[] memory logs)
        internal
        view
        returns (
            bool found,
            address business,
            address payer,
            address token,
            uint256 amount,
            bytes32 paymentId
        )
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            EvmV1Decoder.LogEntry memory log = logs[i];

            if (log.address_ != SOURCE_REGISTRY) continue;
            if (log.topics.length != 4) continue;
            if (log.topics[0] != REVENUE_EVENT_SIGNATURE) continue;
            if (log.data.length != 64) continue;

            business = address(uint160(uint256(log.topics[1])));
            payer = address(uint160(uint256(log.topics[2])));
            paymentId = log.topics[3];

            (token, amount) = abi.decode(log.data, (address, uint256));

            return (true, business, payer, token, amount, paymentId);
        }

        return (false, address(0), address(0), address(0), 0, bytes32(0));
    }
}
