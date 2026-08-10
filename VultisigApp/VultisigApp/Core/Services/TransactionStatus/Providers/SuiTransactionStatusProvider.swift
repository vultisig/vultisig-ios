//
//  SuiTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

/// Sui transaction status over GraphQL RPC.
///
/// The digest is looked up with `transaction(digest:)`. A digest the node cannot
/// resolve comes back as a null transaction with no `errors` — a genuine
/// not-found, safe to keep polling — whereas a refusal arrives as a populated
/// `errors` array that the transport raises, so a persistent node failure is
/// reported instead of being masked as a pending poll forever.
struct SuiTransactionStatusProvider: TransactionStatusProvider {
    /// Walks the same host list `SuiService` uses, so the poller queries the
    /// node that broadcast the transaction — including the user's custom RPC.
    private let client: SuiFailoverClient

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        resolver: RPCEndpointResolving = CustomRPCStore.shared,
        hosts: [URL] = SuiGraphQLAPI.defaultHosts
    ) {
        self.client = SuiFailoverClient(
            httpClient: httpClient,
            endpoints: SuiEndpointResolver(resolver: resolver, defaultHosts: hosts)
        )
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        // Note what this does NOT do: translate an HTTP status into an outcome.
        // Absence is `transaction: null`, never a 404 — a 404 means the endpoint
        // did not serve the request at all (a wrong custom-RPC path, or the last
        // host in a partial outage). Mapping it to `notFound` would hide a broken
        // endpoint behind "still pending", and would undo the failover client's
        // deliberate refusal to treat a miss plus an unanswered host as a verdict.
        let data = try await client.query(
            SuiGraphQLDocument.transaction,
            variables: ["digest": query.txHash],
            responseType: SuiTransactionData.self,
            shouldTryNextHost: { $0.transaction == nil }
        )

        // A null transaction is host-local absence: the digest has not landed
        // here yet, or this node has pruned it.
        guard let transaction = data.transaction else {
            return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
        }

        // The answer has to be about the transaction we asked about. A custom
        // RPC — or a buggy one — returning a different digest would otherwise
        // have ITS outcome recorded against this send, and the poller writes
        // failure permanently.
        guard let digest = transaction.digest, !digest.isEmpty else {
            throw SuiRPCError.incompleteResponse("transaction record without a digest")
        }
        guard digest == query.txHash else {
            throw SuiRPCError.digestMismatch(requested: query.txHash, returned: digest)
        }

        // A transaction record with no effects is NOT absence — the node knows
        // the digest and has not finished populating it. Reporting `notFound`
        // would misstate what the node said; `pending` is what it means, and
        // both keep the poller running.
        guard let effects = transaction.effects else {
            return TransactionStatusResult(status: .pending, blockNumber: nil, confirmations: nil)
        }

        let blockNumber = effects.checkpoint?.sequenceNumber.map(Int.init)

        switch effects.outcome {
        case .succeeded:
            return TransactionStatusResult(
                status: .confirmed,
                blockNumber: blockNumber,
                confirmations: nil
            )
        case .failed:
            return TransactionStatusResult(
                status: .failed(reason: effects.failureReason ?? "Transaction failed"),
                blockNumber: blockNumber,
                confirmations: nil
            )
        case .undetermined:
            // An absent or unrecognised status must not become a terminal
            // failure: the poller records `failed` permanently, and a status
            // enum Sui adds later would otherwise condemn every transaction
            // carrying it. Keep polling instead.
            return TransactionStatusResult(
                status: .pending,
                blockNumber: blockNumber,
                confirmations: nil
            )
        }
    }
}
