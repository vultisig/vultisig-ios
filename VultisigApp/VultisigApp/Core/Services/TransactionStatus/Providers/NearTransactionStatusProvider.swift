//
//  NearTransactionStatusProvider.swift
//  VultisigApp
//

import Foundation

/// NEAR finality for a broadcast transaction.
///
/// Two rules are load-bearing:
/// - `FINAL` is the only execution status that may be reported as success. An
///   `INCLUDED` / `EXECUTED_OPTIMISTIC` outcome can still be reverted, so those
///   stay `.pending` — and `EXECUTED` means executed optimistically, which is
///   not finality either.
/// - The lookup needs the sender's account id: NEAR has no hash-only lookup, the
///   node is asked by `(tx_hash, sender_account_id)`. Without it the status fails
///   closed instead of reporting an unknown hash as pending forever.
struct NearTransactionStatusProvider: TransactionStatusProvider {

    private static let finalExecutionStatus = "FINAL"

    private let service: NearService

    init(service: NearService = .shared) {
        self.service = service
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        guard let senderAccountId = query.senderAccountId, !senderAccountId.isEmpty else {
            throw NearError.malformedResponse("NEAR status needs the sender account id for \(query.txHash)")
        }

        let outcome: NearTransactionOutcome
        do {
            outcome = try await service.fetchTransactionOutcome(hash: query.txHash, senderAccountId: senderAccountId)
        } catch let error as NearError {
            // The node gave up waiting: the outcome is unknown, not failed.
            if error.isRPCWaitTimeout {
                return Self.pending
            }
            // The node affirmatively has no record of the hash.
            if error.isUnknownTransaction {
                return Self.notFound
            }
            throw error
        }

        // An outcome for a different transaction is never evidence about this
        // one — the caller asked about `query.txHash`.
        if let returnedHash = outcome.returnedHash, returnedHash != query.txHash {
            throw NearError.malformedResponse("NEAR status for \(query.txHash) returned the outcome of \(returnedHash)")
        }

        guard outcome.finalExecutionStatus == Self.finalExecutionStatus else {
            return Self.pending
        }

        switch outcome.status {
        case .success:
            return TransactionStatusResult(status: .confirmed, blockNumber: nil, confirmations: nil)
        case .failure:
            return TransactionStatusResult(
                status: .failed(reason: "transactionFailed".localized),
                blockNumber: nil,
                confirmations: nil
            )
        case .unrecognized(let name):
            throw NearError.malformedResponse("NEAR status carries an unrecognized execution status: \(name)")
        case nil:
            throw NearError.malformedResponse("NEAR status carries no execution status for \(query.txHash)")
        }
    }

    private static var pending: TransactionStatusResult {
        TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
    }

    private static var notFound: TransactionStatusResult {
        TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
    }
}
