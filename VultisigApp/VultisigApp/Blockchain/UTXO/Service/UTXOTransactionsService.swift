import SwiftUI
import WalletCore

enum UTXOTransactionError: Error {
    case invalidURL
    case httpError(Int)
    case apiError(String)
    case unexpectedResponse
    case unknown(Error)
}

class UTXOTransactionsService: ObservableObject {

    private static let httpClient: HTTPClientProtocol = HTTPClient()

    /// Broadcasts a Bitcoin transaction via the Vultisig proxy.
    ///
    /// Field note: the Blockchair-fronted Bitcoin proxy occasionally returns a
    /// txid before the transaction has propagated to the wider mempool, so a
    /// successful response here does not guarantee the network has accepted
    /// the broadcast yet. Callers should treat the txid as best-effort and
    /// poll a separate explorer if confirmation matters.
    static func broadcastBitcoinTransaction(signedTransaction: String, expectedTxid: String) async throws -> String {
        let response = try await httpClient.request(
            BitcoinBroadcastAPI.broadcast(signedTransaction: signedTransaction)
        )
        guard let body = String(data: response.data, encoding: .utf8) else {
            throw UTXOTransactionError.unexpectedResponse
        }

        // The proxy runs with validation disabled, so the body reaches us for any
        // HTTP status: the txid on success, or an error string on failure. The
        // txid is the hash of the exact bytes we broadcast, so an accepted
        // transaction echoes back the txid computed locally at signing time.
        // Anything else is an error body — throw it instead of persisting it as
        // a fake txid.
        let txid = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard txid.caseInsensitiveCompare(expectedTxid) == .orderedSame else {
            throw UTXOTransactionError.apiError(txid)
        }

        return txid
    }

    static func broadcastTransaction(chain: String, signedTransaction: String) async throws -> String {
        let response = try await httpClient.request(
            BlockchairAPI.broadcast(chain: chain, signedTransaction: signedTransaction),
            responseType: BlockchairBroadcastResponse.self
        )

        if response.response.statusCode == 400 {
            let message = response.data.context?.error.map { "Failed to broadcast transaction. Error: \($0)" }
                ?? "Failed to broadcast transaction"
            throw NSError(domain: "BlockchairServiceError", code: 400, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let hash = response.data.data?.transactionHash else {
            throw NSError(domain: "BlockchairServiceError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
        }
        return hash
    }
}
