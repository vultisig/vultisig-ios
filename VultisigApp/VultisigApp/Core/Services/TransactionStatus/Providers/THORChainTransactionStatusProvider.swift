//
//  THORChainTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Midgard action → app status.
///
/// ⚠️ **The outcome is `action.type`. `action.status` is the OUTBOUND.**
/// `status` takes exactly two values, `success` and `pending`, and says whether
/// the outbound legs have been sent — never whether the transaction did what it
/// was asked to. A message THORChain rejected is indexed as
/// `{"type": "failed", "status": "success"}`, so reading `status` reports a
/// refusal as a confirmation, on the very screen that exists to tell the user
/// what happened.
///
/// - `type == "failed"` => FAILED, carrying THORChain's own reason for it
/// - `status == "pending"` => PENDING, the outbound has not been sent yet
/// - anything else => CONFIRMED
struct THORChainTransactionStatusProvider: TransactionStatusProvider {
    /// The one action type that is an outcome this app must report as such.
    private enum ActionType {
        static let failed = "failed"
    }

    /// The only two values Midgard's `status` takes; it describes the OUTBOUND.
    private enum ActionStatus {
        static let success = "success"
    }

    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await httpClient.request(
                THORChainTransactionStatusAPI.getActions(txHash: query.txHash, chain: query.chain),
                responseType: THORChainActionsResponse.self
            )

            let actions = response.data.actions
            guard let newest = actions.first else {
                // Midgard has not indexed this transaction yet.
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // ⚠️ A `failed` action anywhere on the page outranks the newest one.
            // The query is `?txid=`, so every action here describes the SAME
            // transaction — one saying the chain refused it settles the
            // question, wherever it sits in the ordering.
            let action = actions.first { $0.type.lowercased() == ActionType.failed } ?? newest

            return mapActionToStatus(action: action, blockNumber: Int(action.height))

        } catch let error as HTTPError {
            return try handleHTTPError(error)
        }
    }

    private func mapActionToStatus(action: MidgardAction, blockNumber: Int?) -> TransactionStatusResult {
        // ⚠️ Checked before `status`, and deliberately: the failure is already
        // final. A `failed` action whose outbound is still pending is one whose
        // REFUND has not been sent yet — the verdict is not still to come, and
        // waiting for the refund leg to land would report a rejected
        // transaction as in-flight until the poller gave up on it.
        if action.type.lowercased() == ActionType.failed {
            return TransactionStatusResult(
                status: .failed(reason: failureReason(metadata: action.metadata)),
                blockNumber: blockNumber,
                confirmations: nil
            )
        }

        // `pending`, or any status Midgard adds later: not something to call an
        // outcome on, so the poller keeps polling.
        guard action.status.lowercased() == ActionStatus.success else {
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
                confirmations: nil
            )
        }

        // Every other settled type — `swap`, `limit_swap`, `send`, `refund`.
        //
        // `refund` included, which reads odd and is intentional: this provider
        // serves every THORChain transaction, and a refund is a legitimate,
        // non-failed outcome elsewhere (a swap returned over its slip limit, a
        // limit order closing unfilled). The limit-order tracker reads refunds
        // itself, from `MidgardLimitOutcomeResolver`, and labels them there.
        // Nothing here can tell those apart, and calling all of them failures
        // would put a red screen in front of flows this change never looked at.
        return TransactionStatusResult(
            status: .confirmed,
            blockNumber: blockNumber,
            confirmations: nil
        )
    }

    /// THORChain's own account of the refusal, verbatim — `reason` is the
    /// THORNode error string and `code` its tag, both from `metadata.failed`,
    /// which is the block a `failed` action carries.
    ///
    /// `metadata.failed.memo` is deliberately not shown: it is the memo this
    /// app itself sent, echoed back, and it explains nothing the user did not
    /// already do.
    private func failureReason(metadata: MidgardActionMetadata?) -> String {
        var parts: [String] = []

        if let reason = metadata?.failed?.reason?.trimmedNonEmpty {
            parts.append("Reason: \(reason)")
        }
        if let code = metadata?.failed?.code?.trimmedNonEmpty {
            parts.append("Code: \(code)")
        }

        guard !parts.isEmpty else { return "Transaction failed on THORChain" }
        return (["Transaction failed"] + parts).joined(separator: ", ")
    }

    /// Maps HTTP failures to a status.
    /// - 404: Midgard has no action for this txid yet → `.notFound` (keep polling).
    /// - 429 / 5xx: marked `.failed` so the error surfaces to the user.
    /// - timeout / network / other: transport-level, not an on-chain result, so
    ///   thrown — the poller keeps polling and the duplicate-broadcast check keeps
    ///   retrying instead of marking a live tx permanently FAILED.
    private func handleHTTPError(_ error: HTTPError) throws -> TransactionStatusResult {
        if case .statusCode(let code, _) = error {
            if code == 404 {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            if code == 429 {
                return TransactionStatusResult(
                    status: .failed(reason: "Rate limited - too many requests"),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            if code >= 500 {
                return TransactionStatusResult(
                    status: .failed(reason: "Server error: \(code)"),
                    blockNumber: nil,
                    confirmations: nil
                )
            }
        }

        throw error
    }
}
