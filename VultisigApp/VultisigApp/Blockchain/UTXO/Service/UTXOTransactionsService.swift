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

    static func broadcastBitcoinTransaction(signedTransaction: String) async throws -> String {
        let response = try await httpClient.request(
            BitcoinBroadcastAPI.broadcast(signedTransaction: signedTransaction)
        )
        guard let txid = String(data: response.data, encoding: .utf8) else {
            throw NSError(domain: "BlockchairServiceError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
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

    func getAmount(for transaction: UTXOTransactionMempool) -> String {
        if transaction.isSent {
            return formatAmount(transaction.amountSent)
        } else if transaction.isReceived {
            return formatAmount(transaction.amountReceived)
        }
        return ""
    }

    func formatAmount(_ amountSatoshis: Int) -> String {
        let amountBTC = Decimal(amountSatoshis) / 100_000_000
        return amountBTC.formatForDisplay()
    }
}
