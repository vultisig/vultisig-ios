//
//  SuiTransactionStatusProvider.swift
//  VultisigApp
//
//  Created by Claude on 27/01/2025.
//

import Foundation

struct SuiTransactionStatusProvider: TransactionStatusProvider {
    /// Walks the same host list `SuiService` uses, so the poller queries the
    /// node that broadcast the transaction — including the user's custom RPC.
    private let client: SuiFailoverClient

    init(
        httpClient: HTTPClientProtocol = HTTPClient(),
        resolver: RPCEndpointResolving = CustomRPCStore.shared
    ) {
        self.client = SuiFailoverClient(
            httpClient: httpClient,
            endpoints: SuiEndpointResolver(resolver: resolver)
        )
    }

    func checkStatus(query: TransactionStatusQuery) async throws -> TransactionStatusResult {
        do {
            let response = try await client.request(
                responseType: SuiTransactionStatusResponse.self,
                shouldTryNextHost: Self.isHostLocalMiss
            ) { host in
                SuiTransactionStatusAPI.getTransactionBlock(txHash: query.txHash, host: host)
            }

            // Check for RPC error
            if let error = response.error {
                // Error code -32602 typically means transaction not found
                if error.code == -32602 {
                    return TransactionStatusResult(
                        status: .notFound,
                        blockNumber: nil,
                        confirmations: nil
                    )
                }
                // Other error
                return TransactionStatusResult(
                    status: .failed(reason: error.message),
                    blockNumber: nil,
                    confirmations: nil
                )
            }

            // Parse successful response
            if let result = response.result, let effects = result.effects {
                let blockNum = result.checkpoint.flatMap { Int($0) }

                if effects.status.status.lowercased() == "success" {
                    return TransactionStatusResult(
                        status: .confirmed,
                        blockNumber: blockNum,
                        confirmations: nil
                    )
                } else {
                    return TransactionStatusResult(
                        status: .failed(reason: "Transaction failed"),
                        blockNumber: blockNum,
                        confirmations: nil
                    )
                }
            }

            // No result
            return TransactionStatusResult(
                status: .notFound,
                blockNumber: nil,
                confirmations: nil
            )
        } catch let error as HTTPError {
            if case .statusCode(let code, _) = error, code == 404 {
                return TransactionStatusResult(
                    status: .notFound,
                    blockNumber: nil,
                    confirmations: nil
                )
            }
            throw error
        }
    }

    /// Whether a decoded response says "this node has not seen that digest",
    /// as opposed to reporting the transaction's outcome.
    ///
    /// Absence is host-local: a transaction broadcast through the fallback host
    /// is legitimately unknown to the primary, and a pruned or lagging node can
    /// miss a digest its peer already has. Treating the first miss as final
    /// would poll a landed transaction until the poller gave up, so the walk
    /// continues and only reports `notFound` once every host has missed.
    private static func isHostLocalMiss(_ response: SuiTransactionStatusResponse) -> Bool {
        if let error = response.error {
            // -32602 is Sui's "invalid params" for a digest it cannot resolve.
            return error.code == -32602
        }
        return response.result?.effects == nil
    }
}
