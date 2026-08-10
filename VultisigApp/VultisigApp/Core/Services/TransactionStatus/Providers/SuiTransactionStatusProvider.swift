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
        do {
            let data = try await client.query(
                SuiGraphQLDocument.transaction,
                variables: ["digest": query.txHash],
                responseType: SuiTransactionData.self,
                shouldTryNextHost: { $0.transaction == nil }
            )

            // A null transaction is host-local absence: the digest has not
            // landed here yet, or this node has pruned it.
            guard let transaction = data.transaction else {
                return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
            }

            // A transaction record with no effects is NOT absence — the node
            // knows the digest and has not finished populating it. Reporting
            // `notFound` would be a lie about what the node said; `pending` is
            // what it actually means, and both keep the poller running.
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
        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return TransactionStatusResult(status: .notFound, blockNumber: nil, confirmations: nil)
            }
            throw error
        }
    }
}
